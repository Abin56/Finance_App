import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../people/presentation/widgets/share_format.dart';
import '../../domain/expense.dart';

/// Builds a FLOWFI-branded plain-text summary of one split/assigned
/// [Expense] and hands it to the platform's native share sheet — the
/// per-expense counterpart to `ShareStatement` (which summarizes a whole
/// person's history). [installments] is supplied by the caller
/// (`TransactionDetailScreen` already loads them for `_ParticipantsSection`)
/// since this is a pure text builder, no I/O of its own.
abstract class ShareExpense {
  ShareExpense._();

  static String buildText(Expense expense, List<Installment> installments) {
    final installmentByParticipantId = {
      for (final i in installments)
        if (expense.participants.any((p) => p.installmentId == i.id)) i.id: i,
    };

    final collected = installments.fold(0.0, (sum, i) => sum + i.amountPaid);
    final remaining = installments.fold(0.0, (sum, i) => sum + i.remainingAmount);

    final buffer = StringBuffer()
      ..writeln(ShareFormat.header('Expense Sharing Summary'))
      ..writeln()
      ..writeln('Expense Information')
      ..writeln(expense.description)
      ..writeln('Date: ${expense.date.shortDate}')
      ..writeln('Total Bill: ${CurrencyFormatter.instance.format(expense.totalAmount)}')
      ..writeln(ShareFormat.divider)
      ..writeln()
      ..writeln('Payment Summary')
      ..writeln('Collected: ${CurrencyFormatter.instance.format(collected)}')
      ..writeln('Remaining: ${CurrencyFormatter.instance.format(remaining)}')
      ..writeln(ShareFormat.divider)
      ..writeln()
      ..writeln('Split Details');

    for (final participant in expense.participants) {
      final installment = installmentByParticipantId[participant.installmentId];
      final dot = participant.isMe
          ? '✅'
          : installment == null
          ? '⚪'
          : ShareFormat.installmentStatusDot(installment.status);
      buffer
        ..writeln('$dot ${participant.name}')
        ..writeln('  Share      : ${CurrencyFormatter.instance.format(participant.share)}')
        ..writeln('  Paid       : ${CurrencyFormatter.instance.format(installment?.amountPaid ?? participant.share)}')
        ..writeln('  Remaining  : ${CurrencyFormatter.instance.format(installment?.remainingAmount ?? 0)}')
        ..writeln();
    }

    buffer
      ..writeln(ShareFormat.divider)
      ..writeln()
      ..writeln('Overall Status')
      ..writeln('Total Bill  : ${CurrencyFormatter.instance.format(expense.totalAmount)}')
      ..writeln('Collected   : ${CurrencyFormatter.instance.format(collected)}')
      ..writeln('Remaining   : ${CurrencyFormatter.instance.format(remaining)}')
      ..writeln()
      ..writeln('Payment Instructions')
      ..writeln('Please pay your share to settle this expense.')
      ..writeln()
      ..writeln(ShareFormat.footer);

    return buffer.toString();
  }

  static Future<void> share(BuildContext context, Expense expense, List<Installment> installments) {
    final text = buildText(expense, installments);
    return SharePlus.instance.share(ShareParams(text: text, subject: 'Expense: ${expense.description}'));
  }
}
