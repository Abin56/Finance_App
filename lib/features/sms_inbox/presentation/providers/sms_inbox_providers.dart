import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../data/merchant_memory_dao.dart';
import '../../data/merchant_memory_repository.dart';
import '../../data/sms_inbox_dao.dart';
import '../../data/sms_inbox_database.dart';
import '../../data/sms_inbox_repository.dart';
import '../../data/sms_permission_service.dart';
import '../../data/sms_reader_adapter.dart';
import '../../domain/filter/sms_card_matcher.dart';
import '../../domain/filter/sms_filter_criteria.dart';
import '../../domain/merchant/merchant_category_suggester.dart';
import '../../domain/merchant/merchant_memory.dart';
import '../../domain/sms_availability.dart';
import '../../domain/sms_import_status.dart';
import '../../domain/sms_inbox_item.dart';
import '../../domain/sms_transaction_category.dart';

final smsInboxDatabaseProvider = Provider<SmsInboxDatabase>((ref) => SmsInboxDatabase.instance);

final smsInboxDaoProvider = Provider<SmsInboxDao>((ref) => SmsInboxDao(ref.watch(smsInboxDatabaseProvider)));

final smsReaderAdapterProvider = Provider<SmsReaderAdapter>((ref) => const SmsReaderAdapter());

final smsPermissionServiceProvider = Provider<SmsPermissionService>((ref) => const SmsPermissionService());

final smsInboxRepositoryProvider = Provider<SmsInboxRepository>((ref) {
  return SmsInboxRepository(ref.watch(smsInboxDaoProvider), ref.watch(smsReaderAdapterProvider));
});

final merchantMemoryDaoProvider = Provider<MerchantMemoryDao>((ref) {
  return MerchantMemoryDao(ref.watch(smsInboxDatabaseProvider));
});

final merchantMemoryRepositoryProvider = Provider<MerchantMemoryRepository>((ref) {
  return MerchantMemoryRepository(ref.watch(merchantMemoryDaoProvider));
});

/// The user's remembered merchant→category decisions. Loaded once and
/// reloaded only after [record] writes a new one — same "sqflite has no
/// change-stream" rationale as [SmsInboxItemsNotifier].
class MerchantMemoriesNotifier extends AsyncNotifier<List<MerchantMemory>> {
  @override
  Future<List<MerchantMemory>> build() => ref.watch(merchantMemoryRepositoryProvider).getAll();

  /// Remembers a confirmed choice. Callers must only reach here *after* the
  /// receiving screen's own save succeeded — see [MerchantMemoryRepository].
  Future<void> record({
    required String? merchant,
    required TransactionType transactionType,
    required String categoryId,
  }) async {
    await ref.read(merchantMemoryRepositoryProvider).record(
          merchant: merchant,
          transactionType: transactionType,
          categoryId: categoryId,
        );
    state = await AsyncValue.guard(() => ref.read(merchantMemoryRepositoryProvider).getAll());
  }
}

final merchantMemoriesProvider = AsyncNotifierProvider<MerchantMemoriesNotifier, List<MerchantMemory>>(
  MerchantMemoriesNotifier.new,
);

/// The engine behind every pre-filled category. Watches [merchantMemoriesProvider]
/// so a decision the user just made is available to the very next conversion.
final merchantCategorySuggesterProvider = Provider<MerchantCategorySuggester>((ref) {
  return MerchantCategorySuggester(ref.watch(merchantMemoriesProvider).value ?? const []);
});

/// Owns the full, unfiltered list of local `SmsInboxItem`s. sqflite has no
/// native change-stream (unlike Firestore's `watchAll()` elsewhere in this
/// app), so this loads once via `getAll()` and every mutating method here
/// explicitly reloads afterwards — one Notifier remains the single source
/// of truth the rest of the UI reacts to.
class SmsInboxItemsNotifier extends AsyncNotifier<List<SmsInboxItem>> {
  @override
  Future<List<SmsInboxItem>> build() => ref.watch(smsInboxRepositoryProvider).getAll();

  /// Reads the device inbox and stores any newly-discovered financial SMS.
  /// Only ever triggered by an explicit user action (opening/refreshing the
  /// SMS Inbox screen) — never from Dashboard/History load, per the
  /// feature's performance requirement. Returns the number of new items.
  Future<int> scan() async {
    final newCount = await ref.read(smsInboxRepositoryProvider).scanInbox();
    await refresh();
    return newCount;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(smsInboxRepositoryProvider).getAll());
  }

  /// Called only after the receiving screen/sheet's own save has genuinely
  /// succeeded — see `SmsConversionRouter`.
  Future<void> markImported(String id, {required String linkedEntityId, String? linkedEntityRoute}) async {
    await ref.read(smsInboxRepositoryProvider).markImported(id, linkedEntityId: linkedEntityId, linkedEntityRoute: linkedEntityRoute);
    await refresh();
  }

  Future<void> markIgnored(String id) async {
    await ref.read(smsInboxRepositoryProvider).markIgnored(id);
    await refresh();
  }

  /// Ignores many in one batch, reloading the list once at the end — calling
  /// [markIgnored] in a loop instead would reload the whole inbox per id,
  /// which over a large selection is what makes the screen freeze.
  Future<void> markIgnoredMany(List<String> ids) async {
    if (ids.isEmpty) return;
    await ref.read(smsInboxRepositoryProvider).markIgnoredMany(ids);
    await refresh();
  }

  Future<void> restore(String id) async {
    await ref.read(smsInboxRepositoryProvider).restore(id);
    await refresh();
  }

  /// Un-flags a false-positive duplicate — see [SmsInboxRepository].
  Future<void> clearDuplicateFlag(String id) async {
    await ref.read(smsInboxRepositoryProvider).clearDuplicateFlag(id);
    await refresh();
  }

  Future<void> deleteMany(List<String> ids) async {
    await ref.read(smsInboxRepositoryProvider).deleteMany(ids);
    await refresh();
  }
}

final smsInboxItemsProvider = AsyncNotifierProvider<SmsInboxItemsNotifier, List<SmsInboxItem>>(
  SmsInboxItemsNotifier.new,
);

/// The History screen's SMS Inbox badge count — a plain read of the local
/// list already loaded by [smsInboxItemsProvider], never a live device SMS
/// scan, so opening History never pays an SMS-query cost.
///
/// Excludes flagged duplicates: they are not work waiting for the user, and
/// counting them would inflate the badge with messages the inbox doesn't
/// even show.
final smsPendingCountProvider = Provider<int>((ref) {
  final items = ref.watch(smsInboxItemsProvider).value ?? const [];
  return items.where((i) => i.status == SmsImportStatus.pending && !i.isDuplicate).length;
});

/// How many flagged duplicates exist. Gates the Duplicates filter section:
/// an inbox with no duplicates must not offer a filter that can only ever
/// come back empty.
final smsDuplicateCountProvider = Provider<int>((ref) {
  final items = ref.watch(smsInboxItemsProvider).value ?? const [];
  return items.where((item) => item.isDuplicate).length;
});

/// Resolves a duplicate's original for the review UI, which has to show the
/// pair side by side. Returns null if the original was deleted.
final smsDuplicateOriginalProvider = Provider.family<SmsInboxItem?, String>((ref, duplicateId) {
  final items = ref.watch(smsInboxItemsProvider).value ?? const [];
  final duplicate = items.firstWhereOrNull((item) => item.id == duplicateId);
  final originalId = duplicate?.duplicateOfId;
  if (originalId == null) return null;
  return items.firstWhereOrNull((item) => item.id == originalId);
});

class SmsAvailabilityNotifier extends AsyncNotifier<SmsAvailability> {
  @override
  Future<SmsAvailability> build() => ref.watch(smsPermissionServiceProvider).checkStatus();

  Future<void> recheck() async {
    state = await AsyncValue.guard(() => ref.read(smsPermissionServiceProvider).checkStatus());
  }

  /// Shows the OS permission dialog. Callers must show the explanation copy
  /// first — this only wraps the actual request.
  Future<void> request() async {
    state = await AsyncValue.guard(() => ref.read(smsPermissionServiceProvider).requestPermission());
  }

  Future<void> openSettings() => ref.read(smsPermissionServiceProvider).openSettings();
}

final smsAvailabilityProvider = AsyncNotifierProvider<SmsAvailabilityNotifier, SmsAvailability>(
  SmsAvailabilityNotifier.new,
);

/// Live search, kept separate from [smsFilterCriteriaProvider]: typing
/// narrows the feed as you go, whereas the sheet's facets only land on Apply.
final smsSearchQueryProvider = StateProvider<String>((ref) => '');

final smsFilterCriteriaProvider = StateProvider<SmsFilterCriteria>((ref) => const SmsFilterCriteria());

/// Resolves SMS last-4s against the user's cards. Watches the existing cards
/// stream rather than reading it, so adding a card's last-4 immediately makes
/// that card filterable.
final smsCardMatcherProvider = Provider<SmsCardMatcher>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  return SmsCardMatcher.fromCards(cards);
});

/// The banks to actually offer in the filter sheet — derived from the banks
/// present in the scanned messages, never a hardcoded list, so it can't offer
/// a bank the user has no SMS from (or miss one this app has never heard of).
final smsAvailableBanksProvider = Provider<List<String>>((ref) {
  final items = ref.watch(smsInboxItemsProvider).value ?? const [];
  final banks = items.map((item) => item.parsed?.bankName).whereType<String>().toSet().toList();
  banks.sort();
  return banks;
});

/// A selectable card in the filter sheet. Labelled from the card's linked
/// account name plus its last-4, matching how `CreditCardsScreen` names cards.
class SmsCardOption {
  const SmsCardOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Only cards the matcher can actually resolve, plus an explicit "Unknown
/// card" bucket for messages that couldn't be linked to one.
final smsCardFilterOptionsProvider = Provider<List<SmsCardOption>>((ref) {
  final matcher = ref.watch(smsCardMatcherProvider);
  if (!matcher.hasMatchableCards) return const [];

  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final accounts = ref.watch(accountsStreamProvider).value ?? const [];
  final accountNameById = {for (final account in accounts) account.id: account.name};

  final options = <SmsCardOption>[];
  for (final card in cards) {
    if (!matcher.matchableCardIds.contains(card.id)) continue;
    final name = accountNameById[card.accountId] ?? 'Card';
    options.add(SmsCardOption(id: card.id, label: '$name •••• ${card.lastFourDigits}'));
  }
  options.sort((a, b) => a.label.compareTo(b.label));

  return [...options, const SmsCardOption(id: SmsCardMatcher.unknownCardId, label: 'Unknown card')];
});

/// The categories present in the scanned messages, same rationale as
/// [smsAvailableBanksProvider] — only offer what can actually match.
final smsAvailableCategoriesProvider = Provider<List<SmsTransactionCategory>>((ref) {
  final items = ref.watch(smsInboxItemsProvider).value ?? const [];
  final categories = items.map((item) => item.parsed?.category).whereType<SmsTransactionCategory>().toSet().toList();
  categories.sort((a, b) => a.label.compareTo(b.label));
  return categories;
});

/// The list the SMS Inbox screen renders: every facet of
/// [smsFilterCriteriaProvider] ANDed, then the live search query, then sorted.
///
/// Filtering is pure in-memory work over the list [smsInboxItemsProvider]
/// already holds — no Firestore read, and no repository call.
final smsFilteredItemsProvider = Provider<List<SmsInboxItem>>((ref) {
  final items = ref.watch(smsInboxItemsProvider).value ?? const [];
  final criteria = ref.watch(smsFilterCriteriaProvider);
  final query = ref.watch(smsSearchQueryProvider).trim().toLowerCase();

  final context = SmsFilterContext(now: DateTime.now(), cardMatcher: ref.watch(smsCardMatcherProvider));

  final filtered = criteria.apply(items, context);
  if (query.isEmpty) return filtered;

  return filtered.where((item) => _matchesQuery(item, query)).toList();
});

/// Searches the parsed fields plus the raw body, which is what makes a UPI id
/// or a free-text reference findable even though no parser lifts them into
/// their own field.
bool _matchesQuery(SmsInboxItem item, String query) {
  final parsed = item.parsed;
  final haystack = [
    parsed?.merchantOrSender,
    parsed?.bankName,
    item.rawMessage.address,
    parsed?.referenceNumber,
    parsed?.amount.toString(),
    item.rawMessage.body,
  ].whereType<String>().join(' ').toLowerCase();

  return haystack.contains(query);
}
