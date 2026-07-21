import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/presentation/providers/account_providers.dart';
import '../../bills/presentation/widgets/payment_form_sheet.dart';
import '../../categories/presentation/providers/category_providers.dart';
import '../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../emi/presentation/widgets/record_emi_payment_sheet.dart';
import '../../expense/presentation/widgets/assign_expense_sheet.dart';
import '../../expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../lending/presentation/widgets/record_loan_payment_sheet.dart';
import '../../transactions/domain/transaction_type.dart';
import '../../transactions/presentation/screens/add_expense_screen.dart';
import '../../transactions/presentation/screens/transfer_screen.dart';
import '../../transactions/presentation/widgets/money_received_sheet.dart';
import '../domain/sms_conversion_target.dart';
import '../domain/sms_inbox_item.dart';
import '../domain/sms_prefill.dart';
import 'providers/sms_inbox_providers.dart';
import 'widgets/sms_bill_picker_sheet.dart';
import 'widgets/sms_obligation_picker_sheet.dart';

/// Maps a chosen `SmsConversionTarget` to the existing FlowFi screen/sheet
/// that owns that entity type, and marks the source SMS imported only after
/// that screen's own save call has genuinely succeeded. Named to parallel
/// `ReceiptClassificationRouter` (Money Received's purpose→repository
/// dispatch), except this one dispatches to UI, since each target is a
/// different screen reusing a different existing repository — never a
/// repository call this class implements itself.
///
/// Targets are wired in one at a time (see the feature's implementation
/// phases); a target not yet wired shows an informational snackbar instead
/// of silently doing nothing.
class SmsConversionRouter {
  const SmsConversionRouter();

  Future<void> route(BuildContext context, WidgetRef ref, SmsInboxItem item, SmsConversionTarget target) async {
    switch (target) {
      case SmsConversionTarget.ignore:
        await ref.read(smsInboxItemsProvider.notifier).markIgnored(item.id);
        return;
      case SmsConversionTarget.myExpense:
        await AddExpenseScreen.show(
          context,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.expense),
          initialType: TransactionType.expense,
        );
        return;
      case SmsConversionTarget.myIncome:
        await AddExpenseScreen.show(
          context,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.income),
          initialType: TransactionType.income,
        );
        return;
      case SmsConversionTarget.creditCardPurchase:
        await AddExpenseScreen.show(
          context,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.expense),
          initialType: TransactionType.expense,
        );
        return;
      case SmsConversionTarget.someonePaidMe:
        await MoneyReceivedSheet.show(
          context,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.income),
        );
        return;
      case SmsConversionTarget.splitExpense:
        await SplitExpenseFormSheet.show(
          context,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.expense),
        );
        return;
      case SmsConversionTarget.paidForSomeoneElse:
        await AssignExpenseSheet.show(
          context,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.expense),
        );
        return;
      case SmsConversionTarget.loanPayment:
        final picked = await SmsLoanPickerSheet.show(context);
        if (picked == null || !context.mounted) return;
        final (loan, installment) = picked;
        await RecordLoanPaymentSheet.show(
          context,
          installment,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.expense),
        );
        return;
      case SmsConversionTarget.emiPayment:
        final picked = await SmsEmiPickerSheet.show(context);
        if (picked == null || !context.mounted) return;
        final (emi, installment) = picked;
        await RecordEmiPaymentSheet.show(
          context,
          emi,
          installment,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.expense),
        );
        return;
      case SmsConversionTarget.billPayment:
        final bill = await SmsBillPickerSheet.show(context);
        if (bill == null || !context.mounted) return;
        await PaymentFormSheet.show(
          context,
          bill,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.expense),
        );
        return;
      case SmsConversionTarget.transferBetweenAccounts:
        // Source account guessed from the masked number where possible;
        // destination is always left for the user, since an SMS never states
        // which of the user's own accounts it moved into.
        await TransferScreen.show(
          context,
          smsPrefill: _buildPrefill(ref, item, transactionType: TransactionType.expense),
        );
    }
  }

  /// Builds the shared prefill payload, resolving a suggested account/
  /// category where a reliable signal exists. Every resolved value is only
  /// ever an *initial* value on the receiving screen — never locked — so a
  /// wrong guess costs the user one tap to correct, not a wrong balance.
  SmsPrefill _buildPrefill(
    WidgetRef ref,
    SmsInboxItem item, {
    required TransactionType transactionType,
  }) {
    final parsed = item.parsed;

    final categories = ref.read(categoriesForTypeProvider(transactionType));
    final suggestion = ref.read(merchantCategorySuggesterProvider).suggest(
          merchant: parsed?.merchantOrSender,
          transactionType: transactionType,
          categories: categories,
          smsCategory: parsed?.category,
        );

    return SmsPrefill(
      smsId: item.id,
      amount: parsed?.amount ?? 0.0,
      dateTime: item.rawMessage.date,
      merchantOrSender: parsed?.merchantOrSender,
      suggestedCategoryId: suggestion?.categoryId,
      categorySuggestionSource: suggestion?.source,
      suggestedAccountId: _matchAccountId(ref, parsed?.maskedAccountOrCard),
      referenceNumber: parsed?.referenceNumber,
      note: _buildNote(item),
    );
  }

  /// Resolves the account behind a masked last-4 the SMS exposed, checking
  /// both credit cards and plain bank Accounts, but **only when exactly one**
  /// match turns up across the two combined. Two cards, two accounts, or a
  /// card and an account sharing a last-4 is uncommon but entirely real, and
  /// there is nothing else in the SMS to break the tie — so per the feature
  /// spec ("Never guess. If multiple could match, leave unselected") an
  /// ambiguous match yields null and the user picks. Silently taking the
  /// first match would put the spend on the wrong account's statement, which
  /// is a wrong number rather than a missing one.
  String? _matchAccountId(WidgetRef ref, String? maskedAccountOrCard) {
    if (maskedAccountOrCard == null) return null;

    final cards = ref.read(creditCardsStreamProvider).value ?? const [];
    final cardMatches = cards.where((card) => card.lastFourDigits == maskedAccountOrCard).map((c) => c.accountId);

    final accounts = ref.read(accountsStreamProvider).value ?? const [];
    final accountMatches = accounts
        .where((account) => account.accountNumberLast4 == maskedAccountOrCard)
        .map((a) => a.id);

    final matches = {...cardMatches, ...accountMatches};
    return matches.length == 1 ? matches.single : null;
  }

  String? _buildNote(SmsInboxItem item) {
    final parsed = item.parsed;
    if (parsed == null) return null;
    final parts = [
      if (parsed.bankName != null) parsed.bankName,
      if (parsed.referenceNumber != null) 'Ref ${parsed.referenceNumber}',
    ];
    if (parts.isEmpty) return null;
    return 'SMS: ${parts.join(' • ')}';
  }

}

final smsConversionRouterProvider = Provider<SmsConversionRouter>((ref) => const SmsConversionRouter());
