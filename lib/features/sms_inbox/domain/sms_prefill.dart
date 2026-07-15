import 'merchant/merchant_category_suggester.dart';

/// Shared prefill payload passed from the SMS Inbox into whichever existing
/// FlowFi screen/sheet the user picked on the convert sheet. Every field
/// here is a *suggestion* — the receiving screen renders them as normal,
/// fully editable initial values, never as locked/read-only data, since a
/// parsed SMS is a best guess, not ground truth. [smsId] lets the receiving
/// screen tell `SmsInboxRepository.markImported` which row to link once its
/// own save call has genuinely succeeded.
class SmsPrefill {
  const SmsPrefill({
    required this.smsId,
    required this.amount,
    required this.dateTime,
    this.merchantOrSender,
    this.suggestedCategoryId,
    this.categorySuggestionSource,
    this.suggestedAccountId,
    this.referenceNumber,
    this.note,
  });

  final String smsId;
  final double amount;
  final DateTime dateTime;
  final String? merchantOrSender;
  final String? suggestedCategoryId;

  /// Why [suggestedCategoryId] was suggested, so the receiving screen can say
  /// so rather than silently pre-picking a category the user then has to
  /// second-guess. Null whenever [suggestedCategoryId] is null.
  final SuggestionSource? categorySuggestionSource;

  final String? suggestedAccountId;
  final String? referenceNumber;
  final String? note;
}
