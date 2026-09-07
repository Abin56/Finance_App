import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../domain/loan_timeline_entry.dart';

/// One row in a loan's honest event Timeline — icon, title, optional
/// subtitle (e.g. which installment, or the field that changed), and date.
/// Purely presentational; every entry it renders was already vetted by
/// [LoanTimelineEntry.build] to trace back to real, reliable data.
class LoanTimelineTile extends StatelessWidget {
  const LoanTimelineTile({super.key, required this.entry});

  final LoanTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Icon(entry.icon, color: entry.color, size: AppSizes.iconSm),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (entry.subtitle != null)
                  Text(
                    entry.subtitle!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(
            entry.date.shortDate,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}
