import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan_payment_history_entry.dart';

/// Read-only detail view for a single [LoanPaymentHistoryEntry] — the
/// payment's amount, date, which installment it applied to, who paid it, its
/// note, and settlement method (when recorded). Mirrors
/// `LoanInstallmentDetailSheet`'s `SectionedFormSheet` usage with
/// `showConfirm: false` for a pure detail view.
class LoanPaymentDetailSheet extends ConsumerWidget {
  const LoanPaymentDetailSheet({super.key, required this.entry});

  final LoanPaymentHistoryEntry entry;

  static Future<void> show(BuildContext context, LoanPaymentHistoryEntry entry) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (_) => LoanPaymentDetailSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final payerPersonId = entry.payerPersonId;
    String payerLabel = 'You';
    if (payerPersonId != null) {
      final match = people.where((p) => p.id == payerPersonId);
      payerLabel = match.isNotEmpty ? match.first.name : 'You';
    }

    return SectionedFormSheet(
      title: 'Payment ${entry.installmentSequenceNumber}',
      description: entry.date.fullDate,
      showConfirm: false,
      onConfirm: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Details'),
          const SizedBox(height: AppSizes.sm),
          _DetailRow(label: 'Payment amount', value: CurrencyFormatter.instance.format(entry.amount)),
          _DetailRow(label: 'Payment date', value: entry.date.fullDate),
          _DetailRow(label: 'Installment', value: '#${entry.installmentSequenceNumber}'),
          _DetailRow(label: 'Paid by', value: payerLabel),
          if (entry.note.isNotEmpty) _DetailRow(label: 'Note', value: entry.note),
          if (entry.payment.settlementMethod?.isNotEmpty == true)
            _DetailRow(label: 'Settlement method', value: entry.payment.settlementMethod!),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: context.textTheme.bodyMedium),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
