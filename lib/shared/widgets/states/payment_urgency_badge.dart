import 'package:flutter/material.dart';

import '../../domain/payment_urgency.dart';

/// A small tinted pill combining [PaymentUrgency.icon]/[label]/[color] —
/// mirrors [MoneyDirectionBadge]'s convention so any EMI/Loan/Bill/Credit
/// Card due-status shows identically wherever it appears (Dashboard,
/// Cash Flow Center, and beyond).
class PaymentUrgencyBadge extends StatelessWidget {
  const PaymentUrgencyBadge({super.key, required this.urgency, this.compact = false});

  final PaymentUrgency urgency;

  /// Smaller padding/text for dense rows instead of a standalone card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = urgency.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(urgency.icon, size: compact ? 12 : 16, color: color),
          const SizedBox(width: 4),
          Text(
            urgency.label,
            style: (compact ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
