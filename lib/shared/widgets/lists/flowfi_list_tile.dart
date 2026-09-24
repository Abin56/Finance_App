import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';

/// The shared row primitive the app was missing — `PersonTile`, `AccountTile`,
/// `LoanTile`, `BillTile`, `HistoryTile`, and `TransactionTile` each used to
/// hand-roll their own row shell (some on the old `ClayCard`, some on a plain
/// `Material`/`InkWell`), so density and tap-target shape drifted between
/// screens. This is the one shape all of them should delegate to: a leading
/// icon/avatar slot, a title + optional supporting subtitle, and a
/// right-aligned trailing slot (typically a [FlowFiAmountText] amount +
/// small status).
class FlowFiListTile extends StatelessWidget {
  const FlowFiListTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingSubtitle,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSizes.md,
      vertical: AppSizes.sm + 2,
    ),
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;

  /// Typically a [FlowFiAmountText] — kept as a generic slot so callers
  /// choose their own semantic color rather than this widget guessing it.
  final Widget? trailing;

  /// A small supporting line under [trailing] (e.g. "Credit"/"10:30 AM").
  final Widget? trailingSubtitle;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DefaultTextStyle.merge(
                      style: const TextStyle(overflow: TextOverflow.ellipsis),
                      maxLines: 1,
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        style: const TextStyle(overflow: TextOverflow.ellipsis),
                        maxLines: 1,
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSizes.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    trailing!,
                    if (trailingSubtitle != null) ...[
                      const SizedBox(height: 2),
                      trailingSubtitle!,
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
