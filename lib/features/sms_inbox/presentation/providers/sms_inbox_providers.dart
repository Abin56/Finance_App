import 'package:cloud_functions/cloud_functions.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/services/local_settings_service.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../data/cloud_function_financial_event_ai_provider.dart';
import '../../data/financial_event_dao.dart';
import '../../data/merchant_memory_dao.dart';
import '../../data/merchant_memory_repository.dart';
import '../../data/sms_inbox_dao.dart';
import '../../data/sms_inbox_database.dart';
import '../../data/sms_inbox_repository.dart';
import '../../data/sms_permission_service.dart';
import '../../data/sms_reader_adapter.dart';
import '../../data/sms_transaction_candidate_repository.dart';
import '../../data/transaction_candidate_dao.dart';
import '../../domain/account_card_matcher.dart';
import '../../domain/filter/sms_card_matcher.dart';
import '../../domain/filter/sms_filter_criteria.dart';
import '../../domain/financial_event/automation_action.dart';
import '../../domain/financial_event/automation_policy.dart';
import '../../domain/financial_event/category_resolver.dart';
import '../../domain/financial_event/financial_event.dart';
import '../../domain/financial_event/financial_event_ai_provider.dart';
import '../../domain/financial_event/financial_event_confidence_engine.dart';
import '../../domain/financial_event/financial_event_evidence_link.dart';
import '../../domain/financial_event/financial_event_extractor.dart';
import '../../domain/financial_event/merchant_identity_cache.dart';
import '../../domain/financial_event/financial_event_role.dart';
import '../../domain/financial_event/financial_event_status.dart';
import '../../domain/financial_event/financial_event_type.dart';
import '../../domain/financial_event/transaction_matcher.dart';
import '../../domain/merchant/merchant_category_suggester.dart';
import '../../domain/merchant/merchant_memory.dart';
import '../../domain/sms_availability.dart';
import '../../domain/sms_import_status.dart';
import '../../domain/sms_inbox_item.dart';
import '../../domain/sms_transaction_candidate_cloud.dart';
import '../../domain/sms_transaction_category.dart';
import '../../domain/sms_transaction_direction.dart';
import '../../domain/transaction_candidate.dart';
import '../../domain/transaction_candidate_builder.dart';
import '../sms_candidate_cloud_sync.dart';

final smsInboxDatabaseProvider = Provider<SmsInboxDatabase>(
  (ref) => SmsInboxDatabase.instance,
);

final smsInboxDaoProvider = Provider<SmsInboxDao>(
  (ref) => SmsInboxDao(ref.watch(smsInboxDatabaseProvider)),
);

final smsReaderAdapterProvider = Provider<SmsReaderAdapter>(
  (ref) => const SmsReaderAdapter(),
);

final smsPermissionServiceProvider = Provider<SmsPermissionService>(
  (ref) => const SmsPermissionService(),
);

final smsInboxRepositoryProvider = Provider<SmsInboxRepository>((ref) {
  return SmsInboxRepository(
    ref.watch(smsInboxDaoProvider),
    ref.watch(smsReaderAdapterProvider),
  );
});

final transactionCandidateDaoProvider = Provider<TransactionCandidateDao>((
  ref,
) {
  return TransactionCandidateDao(ref.watch(smsInboxDatabaseProvider));
});

/// Cloud-facing repository for `SmsTransactionCandidateCloud` — same
/// `users/{uid}/...` scoping pattern as every other feature's repository
/// provider (e.g. `accountRepositoryProvider`).
final smsTransactionCandidateRepositoryProvider =
    Provider<SmsTransactionCandidateRepository>((ref) {
      final firestore = ref.watch(firestoreProvider);
      final uid = ref.watch(currentUserIdProvider);
      final collection = firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .collection(FirestoreCollections.smsTransactionCandidates)
          .withConverter<SmsTransactionCandidateCloud>(
            fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
            toFirestore: (candidate, _) => candidate.toFirestore(),
          );
      return SmsTransactionCandidateRepository(collection);
    });

final smsCandidateCloudSyncProvider = Provider<SmsCandidateCloudSync>((ref) {
  return SmsCandidateCloudSync(
    ref.watch(smsTransactionCandidateRepositoryProvider),
    ref.watch(transactionCandidateDaoProvider),
    ref.watch(smsInboxRepositoryProvider),
  );
});

/// Every locally-built `TransactionCandidate` — sqflite has no native
/// change-stream (same reason [SmsInboxItemsNotifier] reloads explicitly),
/// so this is invalidated by [SmsInboxItemsNotifier._generateCandidatesForPending]
/// right after it persists new rows, rather than polled.
final transactionCandidatesProvider =
    FutureProvider<List<TransactionCandidate>>((ref) {
      return ref.watch(transactionCandidateDaoProvider).getAll();
    });

final financialEventDaoProvider = Provider<FinancialEventDao>((ref) {
  return FinancialEventDao(ref.watch(smsInboxDatabaseProvider));
});

/// The concrete AI provider backing the hybrid engine — calls the
/// `classifyFinancialSms` Cloud Function. Swappable seam: a future "AI
/// processing" toggle can point this at [NoopFinancialEventAiProvider]
/// instead without touching anything else in the pipeline.
final financialEventAiProviderProvider = Provider<FinancialEventAiProvider>((
  ref,
) {
  return CloudFunctionFinancialEventAiProvider(FirebaseFunctions.instance);
});

/// Wraps [merchantCategorySuggesterProvider] with the AI-inference tier —
/// see [CategoryResolver].
final categoryResolverProvider = Provider<CategoryResolver>((ref) {
  return CategoryResolver(ref.watch(merchantCategorySuggesterProvider));
});

const _smsAutoCreateSettingKey = 'sms_financial_event_auto_create_enabled';

/// Whether `AutomationPolicy.decide` is allowed to recommend
/// [AutomationAction.createTransaction] at all — default false. Even when
/// true, this phase's pipeline never executes it (see [AutomationAction]'s
/// doc comment); the setting exists so a later phase can flip real
/// auto-execution on without a code change once confidence calibration has
/// been validated against real usage. No settings UI reads/writes this key
/// yet — a future screen does so via [LocalSettingsService.setBool] plus
/// `ref.invalidate(smsAutoCreateSettingProvider)`.
final smsAutoCreateSettingProvider = Provider<bool>((ref) {
  return LocalSettingsService.getBool(
    _smsAutoCreateSettingKey,
    defaultValue: false,
  );
});

/// Every locally-built `FinancialEvent` — same "sqflite has no
/// change-stream" rationale as [transactionCandidatesProvider], invalidated
/// by [SmsInboxItemsNotifier._generateFinancialEventsForPending] after it
/// persists new rows.
final financialEventsProvider = FutureProvider<List<FinancialEvent>>((ref) {
  return ref.watch(financialEventDaoProvider).getAll();
});

/// The [FinancialEvent] linked to one SMS, if any — backs the SMS Inbox
/// detail view's event-type/role chip (see `SmsCandidateSummary`).
final financialEventForSmsItemProvider =
    FutureProvider.family<FinancialEvent?, String>((ref, smsItemId) {
      return ref.watch(financialEventDaoProvider).getEventForSmsItem(smsItemId);
    });

final merchantMemoryDaoProvider = Provider<MerchantMemoryDao>((ref) {
  return MerchantMemoryDao(ref.watch(smsInboxDatabaseProvider));
});

final merchantMemoryRepositoryProvider = Provider<MerchantMemoryRepository>((
  ref,
) {
  return MerchantMemoryRepository(ref.watch(merchantMemoryDaoProvider));
});

/// The user's remembered merchant→category decisions. Loaded once and
/// reloaded only after [record] writes a new one — same "sqflite has no
/// change-stream" rationale as [SmsInboxItemsNotifier].
class MerchantMemoriesNotifier extends AsyncNotifier<List<MerchantMemory>> {
  @override
  Future<List<MerchantMemory>> build() =>
      ref.watch(merchantMemoryRepositoryProvider).getAll();

  /// Remembers a confirmed choice. Callers must only reach here *after* the
  /// receiving screen's own save succeeded — see [MerchantMemoryRepository].
  Future<void> record({
    required String? merchant,
    required TransactionType transactionType,
    required String categoryId,
  }) async {
    await ref
        .read(merchantMemoryRepositoryProvider)
        .record(
          merchant: merchant,
          transactionType: transactionType,
          categoryId: categoryId,
        );
    state = await AsyncValue.guard(
      () => ref.read(merchantMemoryRepositoryProvider).getAll(),
    );
  }
}

final merchantMemoriesProvider =
    AsyncNotifierProvider<MerchantMemoriesNotifier, List<MerchantMemory>>(
      MerchantMemoriesNotifier.new,
    );

/// The engine behind every pre-filled category. Watches [merchantMemoriesProvider]
/// so a decision the user just made is available to the very next conversion.
final merchantCategorySuggesterProvider = Provider<MerchantCategorySuggester>((
  ref,
) {
  return MerchantCategorySuggester(
    ref.watch(merchantMemoriesProvider).value ?? const [],
  );
});

/// Owns the full, unfiltered list of local `SmsInboxItem`s. sqflite has no
/// native change-stream (unlike Firestore's `watchAll()` elsewhere in this
/// app), so this loads once via `getAll()` and every mutating method here
/// explicitly reloads afterwards — one Notifier remains the single source
/// of truth the rest of the UI reacts to.
class SmsInboxItemsNotifier extends AsyncNotifier<List<SmsInboxItem>> {
  @override
  Future<List<SmsInboxItem>> build() =>
      ref.watch(smsInboxRepositoryProvider).getAll();

  /// Reads the device inbox and stores any newly-discovered financial SMS.
  /// Only ever triggered by an explicit user action (opening/refreshing the
  /// SMS Inbox screen) — never from Dashboard/History load, per the
  /// feature's performance requirement. Returns the number of new items.
  ///
  /// A failed read (permission revoked mid-session, or a plugin/platform
  /// exception) is caught here rather than left unhandled — it puts this
  /// state into `AsyncError`, which `SmsInboxScreen`'s existing
  /// `itemsAsync.when(error: ...)` branch already renders, instead of
  /// silently doing nothing.
  Future<int> scan() async {
    try {
      final newCount = await ref.read(smsInboxRepositoryProvider).scanInbox();
      await refresh();
      await _generateFinancialEventsForPending();
      await _generateCandidatesForPending();
      await _syncCandidatesToCloud();
      return newCount;
    } catch (e, st) {
      state = AsyncError(e, st);
      return 0;
    }
  }

  /// Builds and persists a `FinancialEvent` for every parsed, pending SMS
  /// that isn't already linked to one — the AI-hybrid engine's entry point.
  /// Additive to [_generateCandidatesForPending] (which keeps running
  /// unchanged, see that method's own doc) and isolated from [scan]'s error
  /// handling the same way: the SMS rows themselves are already safely
  /// stored by the time this runs, so a failure here (AI call, DB write)
  /// must never turn an otherwise successful scan into an `AsyncError`.
  ///
  /// IMPORTANT: this only ever *computes and stores* `AutomationAction` —
  /// it never calls `TransactionRepository.createTransaction()`. Every
  /// event surfaces through the existing manual `SmsConvertSheet`/
  /// `SmsConversionRouter` flow regardless of confidence. See
  /// `AutomationAction`'s doc comment for why.
  Future<void> _generateFinancialEventsForPending() async {
    try {
      final eventDao = ref.read(financialEventDaoProvider);
      final alreadyLinked = await eventDao.smsItemIdsWithLinks();

      final pending = await ref
          .read(smsInboxRepositoryProvider)
          .getByStatus(SmsImportStatus.pending);
      final toProcess = pending
          .where(
            (item) => item.parsed != null && !alreadyLinked.contains(item.id),
          )
          .toList();
      if (toProcess.isEmpty) return;

      final accountMatcher = AccountCardMatcher(
        accounts: ref.read(accountsStreamProvider).value ?? const [],
        cards: ref.read(activeCreditCardsProvider),
      );
      final extractor = FinancialEventExtractor(
        aiProvider: ref.read(financialEventAiProviderProvider),
        categoryResolver: ref.read(categoryResolverProvider),
        // One cache per scan — a run of SMS from the same merchant (a
        // week of Swiggy orders, a month of the same EMI) shares one
        // resolved identity instead of repeating catalog lookups or, more
        // importantly, AI calls. See `MerchantIdentityCache`'s doc comment.
        merchantIdentityCache: MerchantIdentityCache(),
      );
      final matcher = TransactionMatcher(eventDao);
      const confidenceEngine = FinancialEventConfidenceEngine();
      const policy = AutomationPolicy();
      final autoCreateEnabled = ref.read(smsAutoCreateSettingProvider);

      for (final item in toProcess) {
        await _processOneItemForFinancialEvent(
          item: item,
          eventDao: eventDao,
          accountMatcher: accountMatcher,
          extractor: extractor,
          matcher: matcher,
          confidenceEngine: confidenceEngine,
          policy: policy,
          autoCreateEnabled: autoCreateEnabled,
        );
      }
      ref.invalidate(financialEventsProvider);
    } catch (e, st) {
      debugPrint(
        'FinancialEvent generation failed (SMS scan itself still succeeded): $e\n$st',
      );
    }
  }

  /// One item's worth of the hybrid pipeline — extract → score → match →
  /// decide → persist. Split out of [_generateFinancialEventsForPending]
  /// purely for readability; a failure in one item's AI call/DB write must
  /// not stop the rest of [toProcess] from being handled, so this is
  /// deliberately called from inside the loop's own try scope, not wrapped
  /// again here (the outer method's catch already covers it — one failing
  /// item degrades to "processed on a later scan", never a lost item).
  Future<void> _processOneItemForFinancialEvent({
    required SmsInboxItem item,
    required FinancialEventDao eventDao,
    required AccountCardMatcher accountMatcher,
    required FinancialEventExtractor extractor,
    required TransactionMatcher matcher,
    required FinancialEventConfidenceEngine confidenceEngine,
    required AutomationPolicy policy,
    required bool autoCreateEnabled,
  }) async {
    final parsed = item.parsed!;
    final accountMatch = accountMatcher.match(parsed);
    final transactionType = parsed.direction == SmsTransactionDirection.credit
        ? TransactionType.income
        : TransactionType.expense;
    final categories = ref.read(categoriesForTypeProvider(transactionType));

    final extracted = await extractor.extract(
      item: item,
      accountMatch: accountMatch,
      categories: categories,
      accountCardMatcher: accountMatcher,
    );

    final scored = confidenceEngine.score(extracted);
    final isLikelyRefundOrReversal =
        extracted.eventType == FinancialEventType.refund ||
        extracted.eventType == FinancialEventType.reversal;
    final outcome = await matcher.match(
      extracted,
      isLikelyRefundOrReversal: isLikelyRefundOrReversal,
    );

    final decision = policy.decide(
      AutomationPolicyInput(
        confidenceLevel: scored.level,
        accountResolved: extracted.accountMatch.value != null,
        amountValid:
            extracted.amount.value != null && extracted.amount.value! > 0,
        moneyMovement: extracted.moneyMovement.value ?? true,
        matchResult: outcome.result,
        autoCreateEnabled: autoCreateEnabled,
      ),
    );

    final scoredEvent = extracted.copyWith(
      overallConfidence: scored.overall,
      confidenceLevel: scored.level,
    );
    final now = DateTime.now();

    switch (outcome.result) {
      case FinancialEventMatchResult.newEvent:
        final finalEvent = scoredEvent.copyWith(automationAction: decision);
        await eventDao.upsert(finalEvent);
        await eventDao.linkSms(
          FinancialEventEvidenceLink(
            id: IdGenerator.generate(),
            financialEventId: finalEvent.id,
            smsItemId: item.id,
            linkType: FinancialEventLinkType.newEvent,
            confidence: scored.overall,
            linkedAt: now,
          ),
        );
      case FinancialEventMatchResult.existingEvent:
        final matchedId = outcome.matchedEventId!;
        final existing = await eventDao.getById(matchedId);
        if (existing != null) {
          // Two independent SMS agreeing on the same event is itself
          // corroborating evidence — bump confidence rather than leaving it
          // at whatever the first SMS alone produced, but never past 1.0.
          final bumped = existing.copyWith(
            overallConfidence: (existing.overallConfidence + 0.1).clamp(
              0.0,
              1.0,
            ),
          );
          await eventDao.upsert(bumped);
        }
        await eventDao.linkSms(
          FinancialEventEvidenceLink(
            id: IdGenerator.generate(),
            financialEventId: matchedId,
            smsItemId: item.id,
            linkType: FinancialEventLinkType.additionalEvidence,
            confidence: scored.overall,
            linkedAt: now,
          ),
        );
      case FinancialEventMatchResult.refundOfExisting:
      case FinancialEventMatchResult.reversalOfExisting:
        final finalEvent = scoredEvent.copyWith(
          role: FinancialEventRole.linkedSettlement,
          linkedEventId: outcome.matchedEventId,
          status: FinancialEventStatus.linked,
          automationAction: decision,
        );
        await eventDao.upsert(finalEvent);
        await eventDao.linkSms(
          FinancialEventEvidenceLink(
            id: IdGenerator.generate(),
            financialEventId: finalEvent.id,
            smsItemId: item.id,
            linkType:
                outcome.result == FinancialEventMatchResult.refundOfExisting
                ? FinancialEventLinkType.refundOf
                : FinancialEventLinkType.reversalOf,
            confidence: scored.overall,
            linkedAt: now,
          ),
        );
      case FinancialEventMatchResult.possibleDuplicate:
        final finalEvent = scoredEvent.copyWith(
          automationAction: AutomationAction.needsReview,
          needsReview: true,
        );
        await eventDao.upsert(finalEvent);
        await eventDao.linkSms(
          FinancialEventEvidenceLink(
            id: IdGenerator.generate(),
            financialEventId: finalEvent.id,
            smsItemId: item.id,
            linkType: FinancialEventLinkType.possibleDuplicate,
            confidence: scored.overall,
            linkedAt: now,
          ),
        );
      case FinancialEventMatchResult.resolvesPriorEvent:
        // A real transaction resolving an earlier reminder/failed/pending
        // event — the earlier event is left untouched (still real history);
        // this candidate becomes its own new event, linked to it.
        final finalEvent = scoredEvent.copyWith(
          linkedEventId: outcome.matchedEventId,
          automationAction: decision,
        );
        await eventDao.upsert(finalEvent);
        await eventDao.linkSms(
          FinancialEventEvidenceLink(
            id: IdGenerator.generate(),
            financialEventId: finalEvent.id,
            smsItemId: item.id,
            linkType: FinancialEventLinkType.newEvent,
            confidence: scored.overall,
            linkedAt: now,
          ),
        );
      case FinancialEventMatchResult.updateExisting:
        // Reserved — TransactionMatcher never returns this result yet.
        break;
    }
  }

  /// Builds and persists a `TransactionCandidate` for every parsed, pending
  /// SMS that doesn't have one yet. Additive to the scan above and
  /// deliberately isolated from its error handling: the SMS rows themselves
  /// are already safely stored by the time this runs, so a failure here
  /// (e.g. reading the account streams) must never turn an otherwise
  /// successful scan into an `AsyncError` the user sees.
  Future<void> _generateCandidatesForPending() async {
    try {
      final dao = ref.read(transactionCandidateDaoProvider);
      final alreadyBuilt = await dao.existingSmsItemIds();

      final pending = await ref
          .read(smsInboxRepositoryProvider)
          .getByStatus(SmsImportStatus.pending);
      final toBuild = pending.where(
        (item) => item.parsed != null && !alreadyBuilt.contains(item.id),
      );
      if (toBuild.isEmpty) return;

      final matcher = AccountCardMatcher(
        accounts: ref.read(accountsStreamProvider).value ?? const [],
        cards: ref.read(activeCreditCardsProvider),
      );
      final builder = TransactionCandidateBuilder(matcher);

      for (final item in toBuild) {
        final candidate = builder.build(item);
        if (candidate != null) await dao.upsert(candidate);
      }
      ref.invalidate(transactionCandidatesProvider);
    } catch (e, st) {
      debugPrint(
        'TransactionCandidate generation failed (SMS scan itself still succeeded): $e\n$st',
      );
    }
  }

  /// Mirrors `users/{uid}/smsTransactionCandidates` to whatever is still
  /// pending/non-duplicate locally — see `SmsCandidateCloudSync`. Isolated
  /// in its own try/catch for the same reason as
  /// [_generateCandidatesForPending]: local scanning/candidate-generation
  /// has already fully succeeded by the time this runs, and Firestore being
  /// unreachable (offline, rules issue, etc.) must never be reported to the
  /// user as a failed SMS scan, nor leave any local data touched — this
  /// method only ever reads local storage, never writes it.
  Future<void> _syncCandidatesToCloud() async {
    try {
      await ref.read(smsCandidateCloudSyncProvider).sync();
    } catch (e, st) {
      debugPrint(
        'SMS candidate cloud sync failed (local SMS scan itself still succeeded): $e\n$st',
      );
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(smsInboxRepositoryProvider).getAll(),
    );
  }

  /// Called only after the receiving screen/sheet's own save has genuinely
  /// succeeded — see `SmsConversionRouter`.
  Future<void> markImported(
    String id, {
    required String linkedEntityId,
    String? linkedEntityRoute,
  }) async {
    await ref
        .read(smsInboxRepositoryProvider)
        .markImported(
          id,
          linkedEntityId: linkedEntityId,
          linkedEntityRoute: linkedEntityRoute,
        );
    await refresh();
    await _removeCloudCandidate(id);
  }

  Future<void> markIgnored(String id) async {
    await ref.read(smsInboxRepositoryProvider).markIgnored(id);
    await refresh();
    await _removeCloudCandidate(id);
  }

  /// Ignores many in one batch, reloading the list once at the end — calling
  /// [markIgnored] in a loop instead would reload the whole inbox per id,
  /// which over a large selection is what makes the screen freeze.
  Future<void> markIgnoredMany(List<String> ids) async {
    if (ids.isEmpty) return;
    await ref.read(smsInboxRepositoryProvider).markIgnoredMany(ids);
    await refresh();
    for (final id in ids) {
      await _removeCloudCandidate(id);
    }
  }

  /// Deletes [id]'s cloud candidate doc (if any) right away, so the web
  /// Transaction Studio stops showing it the moment there's nothing left to
  /// review — rather than waiting for the next [scan]'s full
  /// [SmsCandidateCloudSync.sync] reconciliation, which still runs as the
  /// safety net that catches anything missed here (e.g. a duplicate flagged
  /// without ever going through markImported/markIgnored).
  ///
  /// Best-effort and isolated, same rationale as [_syncCandidatesToCloud]:
  /// local state (the mark above) has already succeeded, so a missing
  /// document, an offline device, or a Firestore error here must never be
  /// surfaced as a failed conversion/ignore, nor retried — the next sync()
  /// will clean it up.
  Future<void> _removeCloudCandidate(String id) async {
    try {
      await ref.read(smsTransactionCandidateRepositoryProvider).deleteById(id);
    } catch (e, st) {
      debugPrint(
        'SMS cloud candidate cleanup failed for $id (local state already updated): $e\n$st',
      );
    }
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

  /// Deletes the SMS rows, then their local `TransactionCandidate` rows (if
  /// any) — see [TransactionCandidateDao.deleteBySmsItemIds]'s own doc: a
  /// candidate must never outlive the message it was built from. Cloud
  /// candidates aren't touched here; a hard-deleted SMS is no longer
  /// `pending`, so the next [scan]'s [SmsCandidateCloudSync.sync] already
  /// removes its cloud doc the same way it does for converted/ignored SMS.
  Future<void> deleteMany(List<String> ids) async {
    await ref.read(smsInboxRepositoryProvider).deleteMany(ids);
    await ref.read(transactionCandidateDaoProvider).deleteBySmsItemIds(ids);
    // Only removes this SMS's own link row — the FinancialEvent itself (and
    // any other SMS still linked to it) is left untouched, which is exactly
    // what structurally fixes the old orphaned-duplicate bug. See
    // FinancialEventDao.deleteLinksForSmsIds's doc comment.
    await ref.read(financialEventDaoProvider).deleteLinksForSmsIds(ids);
    await refresh();
    ref.invalidate(financialEventsProvider);
  }
}

final smsInboxItemsProvider =
    AsyncNotifierProvider<SmsInboxItemsNotifier, List<SmsInboxItem>>(
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
  return items
      .where((i) => i.status == SmsImportStatus.pending && !i.isDuplicate)
      .length;
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
final smsDuplicateOriginalProvider = Provider.family<SmsInboxItem?, String>((
  ref,
  duplicateId,
) {
  final items = ref.watch(smsInboxItemsProvider).value ?? const [];
  final duplicate = items.firstWhereOrNull((item) => item.id == duplicateId);
  final originalId = duplicate?.duplicateOfId;
  if (originalId == null) return null;
  return items.firstWhereOrNull((item) => item.id == originalId);
});

class SmsAvailabilityNotifier extends AsyncNotifier<SmsAvailability> {
  @override
  Future<SmsAvailability> build() =>
      ref.watch(smsPermissionServiceProvider).checkStatus();

  Future<void> recheck() async {
    state = await AsyncValue.guard(
      () => ref.read(smsPermissionServiceProvider).checkStatus(),
    );
  }

  /// Shows the OS permission dialog. Callers must show the explanation copy
  /// first — this only wraps the actual request.
  Future<void> request() async {
    state = await AsyncValue.guard(
      () => ref.read(smsPermissionServiceProvider).requestPermission(),
    );
  }

  Future<void> openSettings() =>
      ref.read(smsPermissionServiceProvider).openSettings();
}

final smsAvailabilityProvider =
    AsyncNotifierProvider<SmsAvailabilityNotifier, SmsAvailability>(
      SmsAvailabilityNotifier.new,
    );

/// Live search, kept separate from [smsFilterCriteriaProvider]: typing
/// narrows the feed as you go, whereas the sheet's facets only land on Apply.
final smsSearchQueryProvider = StateProvider<String>((ref) => '');

final smsFilterCriteriaProvider = StateProvider<SmsFilterCriteria>(
  (ref) => const SmsFilterCriteria(),
);

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
  final banks = items
      .map((item) => item.parsed?.bankName)
      .whereType<String>()
      .toSet()
      .toList();
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
  final accountNameById = {
    for (final account in accounts) account.id: account.name,
  };

  final options = <SmsCardOption>[];
  for (final card in cards) {
    if (!matcher.matchableCardIds.contains(card.id)) continue;
    final name = accountNameById[card.accountId] ?? 'Card';
    options.add(
      SmsCardOption(id: card.id, label: '$name •••• ${card.lastFourDigits}'),
    );
  }
  options.sort((a, b) => a.label.compareTo(b.label));

  return [
    ...options,
    const SmsCardOption(
      id: SmsCardMatcher.unknownCardId,
      label: 'Unknown card',
    ),
  ];
});

/// The categories present in the scanned messages, same rationale as
/// [smsAvailableBanksProvider] — only offer what can actually match.
final smsAvailableCategoriesProvider = Provider<List<SmsTransactionCategory>>((
  ref,
) {
  final items = ref.watch(smsInboxItemsProvider).value ?? const [];
  final categories = items
      .map((item) => item.parsed?.category)
      .whereType<SmsTransactionCategory>()
      .toSet()
      .toList();
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

  final context = SmsFilterContext(
    now: DateTime.now(),
    cardMatcher: ref.watch(smsCardMatcherProvider),
  );

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
