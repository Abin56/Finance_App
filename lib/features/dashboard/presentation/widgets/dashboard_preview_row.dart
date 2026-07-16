import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Shared row grammar for dashboard preview lists: a 44px leading badge,
/// title + caption on the left, amount + status badge on the right. Used by
/// both the Money to Receive (`leading` is a person-initial avatar) and
/// Upcoming Payments (`leading` is a kind icon) preview cards, which used to
/// implement this same layout twice.
class DashboardPreviewRow extends StatelessWidget {
  const DashboardPreviewRow({
    super.key,
    required this.leading,
    required this.title,
    required this.caption,
    required this.amount,
    required this.statusBadge,
    this.captionWidget,
    this.onTap,
  });

  final Widget leading;
  final String title;

  /// Plain caption text, shown when [captionWidget] is null.
  final String caption;

  /// Overrides [caption] when the caption needs more than plain text (e.g.
  /// Money to Receive's settled-ratio progress bar under the name).
  final Widget? captionWidget;
  final double amount;
  final Widget statusBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: [
            leading,
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (captionWidget != null)
                    captionWidget!
                  else
                    Text(
                      caption,
                      style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.instance.format(amount),
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                statusBadge,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
