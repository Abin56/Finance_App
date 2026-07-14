import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/emi_payment_breakdown.dart';
import '../../domain/emi_payment_history_entry.dart';

/// One entry in an EMI's full payment timeline — same visual language as
/// `LedgerTimelineTile`/`PaymentTile` (40x40 tinted icon, title/subtitle,
/// trailing amount + secondary stat) so the app has one consistent timeline
/// UI across People Ledger, Bills, and EMI. When [EmiPaymentHistoryEntry.breakdown]
/// is present (payments recorded through `RecordEmiPaymentSheet`), tapping
/// the row expands a detailed charge breakdown; payments with no breakdown
/// (recorded before this feature, or via the multi-payment sheet) render
/// exactly as before, with no expand affordance.
class EmiPaymentHistoryTile extends StatefulWidget {
  const EmiPaymentHistoryTile({super.key, required this.entry, this.onTap});

  final EmiPaymentHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  State<EmiPaymentHistoryTile> createState() => _EmiPaymentHistoryTileState();
}

class _EmiPaymentHistoryTileState extends State<EmiPaymentHistoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final status = entry.status;
    final paidBy = entry.paidBy;
    final breakdown = entry.breakdown;
    final subtitleParts = <String>[
      entry.date.shortDate,
      if (paidBy != null) 'Paid by $paidBy' else if (entry.note.isNotEmpty) entry.note,
    ];

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: breakdown != null ? () => setState(() => _expanded = !_expanded) : widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    child: Icon(status.icon, color: status.color, size: AppSizes.iconSm),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payment ${entry.installmentSequenceNumber}', style: context.textTheme.titleMedium),
                        Text(
                          subtitleParts.join(' · '),
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colors.onSurface.withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        entry.status == EmiPaymentHistoryStatus.skipped
                            ? status.label
                            : CurrencyFormatter.instance.format(
                                breakdown?.totalAmountPaid ?? entry.amount,
                              ),
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: status.color,
                        ),
                      ),
                      Text(
                        'Amount left: ${CurrencyFormatter.instance.format(entry.remainingBalanceAfter)}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  if (breakdown != null)
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: context.colors.onSurface.withValues(alpha: 0.4),
                    ),
                ],
              ),
              if (_expanded && breakdown != null) ...[
                const Divider(height: AppSizes.lg),
                _BreakdownGrid(breakdown: breakdown),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownGrid extends StatelessWidget {
  const _BreakdownGrid({required this.breakdown});

  final EmiPaymentBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double)>[
      ('Principal paid', breakdown.principalPaid),
      ('Interest paid', breakdown.interestPaid),
      ('GST', breakdown.gst),
      ('IGST', breakdown.igst),
      ('Processing fee', breakdown.processingFee),
      ('Insurance charge', breakdown.insuranceCharge),
      ('Service charge', breakdown.serviceCharge),
      ('Penalty', breakdown.penalty),
      ('Other charges', breakdown.otherCharges),
    ].where((row) => row.$2 != 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  row.$1,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(CurrencyFormatter.instance.format(row.$2), style: context.textTheme.bodySmall),
              ],
            ),
          ),
        if (breakdown.notes.isNotEmpty) ...[
          const SizedBox(height: AppSizes.xs),
          Text(
            breakdown.notes,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: AppSizes.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total amount paid', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              CurrencyFormatter.instance.format(breakdown.totalAmountPaid),
              style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
