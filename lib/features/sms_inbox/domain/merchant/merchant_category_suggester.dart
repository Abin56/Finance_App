import '../../../categories/domain/category.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../sms_transaction_category.dart';
import 'merchant_key.dart';
import 'merchant_memory.dart';
import 'merchant_seed_catalog.dart';

/// Where a suggested category came from. The UI shows this so a suggestion is
/// always explainable ("Because you filed Swiggy under Food & Dining before")
/// rather than an unattributed guess the user has to second-guess.
enum SuggestionSource { userHistory, knownMerchant, smsType }

/// A suggested category plus why it was suggested. Never a decision — the
/// receiving screen renders it as an editable initial value, exactly as
/// `SmsPrefill` documents.
class CategorySuggestion {
  const CategorySuggestion({required this.categoryId, required this.source});

  final String categoryId;
  final SuggestionSource source;
}

/// Decides which category to pre-fill for a converting SMS.
///
/// Strictly ranked, most-personal first:
///
///  1. [SuggestionSource.userHistory] — what this user has actually chosen
///     for this merchant before. Always wins; it is the only signal that is
///     evidence about *this* user rather than a generalization.
///  2. [SuggestionSource.knownMerchant] — `MerchantSeedCatalog`'s starter map,
///     so a first-time user still gets Swiggy → Food & Dining.
///  3. [SuggestionSource.smsType] — the coarse parser category (a salary
///     credit is Salary), the only signal available when the merchant is
///     unknown or unparsed.
///
/// Every path resolves to an id from [categories] — the user's own, possibly
/// renamed or custom list. A remembered id that no longer exists, or a seed
/// name the user has no category for, yields no suggestion rather than a
/// stale or invented one. Returning null is a perfectly good outcome: it
/// leaves the picker unset, exactly as a manual entry starts.
class MerchantCategorySuggester {
  const MerchantCategorySuggester(this.memories);

  final List<MerchantMemory> memories;

  CategorySuggestion? suggest({
    required String? merchant,
    required TransactionType transactionType,
    required List<Category> categories,
    SmsTransactionCategory? smsCategory,
  }) {
    if (categories.isEmpty) return null;

    final merchantKey = MerchantKey.normalize(merchant);

    if (merchantKey != null) {
      final remembered = _fromHistory(merchantKey, transactionType, categories);
      if (remembered != null) return remembered;

      final known = _fromSeedCatalog(merchantKey, categories);
      if (known != null) return known;
    }

    return _fromSmsCategory(smsCategory, categories);
  }

  /// The category this user has filed [merchantKey] under most often, with
  /// the most recent choice breaking a tie — so someone who has genuinely
  /// changed their mind converges on the new category as it overtakes the
  /// old, without one stray mis-tap immediately overturning a long history.
  CategorySuggestion? _fromHistory(String merchantKey, TransactionType type, List<Category> categories) {
    final candidates = memories
        .where((memory) => memory.merchantKey == merchantKey && memory.transactionType == type)
        .where((memory) => categories.any((category) => category.id == memory.categoryId))
        .toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final byCount = b.timesUsed.compareTo(a.timesUsed);
      return byCount != 0 ? byCount : b.lastUsedAt.compareTo(a.lastUsedAt);
    });

    return CategorySuggestion(categoryId: candidates.first.categoryId, source: SuggestionSource.userHistory);
  }

  CategorySuggestion? _fromSeedCatalog(String merchantKey, List<Category> categories) {
    final id = _resolveByName(MerchantSeedCatalog.categoryNamesFor(merchantKey), categories);
    return id == null ? null : CategorySuggestion(categoryId: id, source: SuggestionSource.knownMerchant);
  }

  CategorySuggestion? _fromSmsCategory(SmsTransactionCategory? smsCategory, List<Category> categories) {
    if (smsCategory == null) return null;

    final candidateNames = switch (smsCategory) {
      SmsTransactionCategory.salaryCredit => const ['Salary'],
      SmsTransactionCategory.cardPurchase ||
      SmsTransactionCategory.creditCardPurchase ||
      SmsTransactionCategory.upiPayment => const ['Shopping'],
      SmsTransactionCategory.billPayment ||
      SmsTransactionCategory.autoDebit => const ['Bills & Utilities', 'Utilities'],
      SmsTransactionCategory.refund || SmsTransactionCategory.atmWithdrawal => const ['Other'],
      _ => const <String>[],
    };

    final id = _resolveByName(candidateNames, categories);
    return id == null ? null : CategorySuggestion(categoryId: id, source: SuggestionSource.smsType);
  }

  /// Resolves the first candidate name that matches one of the user's real
  /// categories. Case-insensitive because a user who renamed "Food & Dining"
  /// to "food & dining" still means the same category.
  String? _resolveByName(List<String> candidateNames, List<Category> categories) {
    for (final name in candidateNames) {
      for (final category in categories) {
        if (category.name.toLowerCase() == name.toLowerCase()) return category.id;
      }
    }
    return null;
  }
}
