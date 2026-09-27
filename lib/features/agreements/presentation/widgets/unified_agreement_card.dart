import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../domain/unified_finance_agreement.dart';
import '../../domain/unified_workspace_model.dart';

class UnifiedAgreementCard extends StatelessWidget {
  const UnifiedAgreementCard({
    super.key,
    required this.agreement,
    required this.onTap,
  });
  final UnifiedFinanceAgreement agreement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final presentation = agreementCardPresentation(agreement);
    final progress = agreement.originalPrincipal <= 0
        ? 0.0
        : ((agreement.originalPrincipal - agreement.remainingPrincipal) /
                  agreement.originalPrincipal)
              .clamp(0.0, 1.0);
    final statusColor = switch (agreement.status) {
      UnifiedAgreementStatus.overdue ||
      UnifiedAgreementStatus.defaulted => context.colors.error,
      UnifiedAgreementStatus.dueSoon => context.colors.tertiary,
      UnifiedAgreementStatus.closed => context.colors.outline,
      _ => context.colors.primary,
    };
    final icon =
        agreement.agreementKind == UnifiedAgreementKind.installmentPurchase
        ? Icons.shopping_bag_outlined
        : agreement.direction == UnifiedAgreementDirection.lent
        ? Icons.handshake_outlined
        : Icons.account_balance_outlined;

    return Semantics(
      button: true,
      label:
          'Open ${agreement.title}, ${presentation.relationship}, ${statusLabel(agreement.status)}',
      child: FlowFiCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: context.colors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agreement.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        agreement.providerName ?? presentation.relationship,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel(agreement.status),
                    style: context.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              presentation.relationship,
              style: context.textTheme.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              presentation.remainingLabel,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                CurrencyFormatter.instance.format(agreement.remainingPrincipal),
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (presentation.representedOnCard)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.credit_card,
                      size: 14,
                      color: context.colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Tracked in the linked credit card balance',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: context.colors.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).round()}% of principal repaid',
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _Metric(
                    label:
                        agreement.repaymentType ==
                            UnifiedRepaymentType.scheduled
                        ? 'Installment'
                        : 'Repayment',
                    value:
                        agreement.repaymentType ==
                                UnifiedRepaymentType.scheduled &&
                            agreement.installmentAmount != null
                        ? CurrencyFormatter.instance.format(
                            agreement.installmentAmount!,
                          )
                        : presentation.repaymentLabel ?? 'Scheduled',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    label: 'Next due',
                    value: agreement.nextDueDate == null
                        ? 'No payment due'
                        : DateFormat('d MMM').format(agreement.nextDueDate!),
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });
  final String label;
  final String value;
  final bool alignEnd;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: context.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
