import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../shared/widgets/states/shimmer_box.dart';

/// Skeleton rows shown while the inbox loads — mirrors [SmsMessageTile]'s
/// geometry so the list doesn't visibly reflow when real data arrives.
/// Reuses the app's shared [ShimmerBox] rather than a bare spinner.
class SmsInboxSkeletonList extends StatelessWidget {
  const SmsInboxSkeletonList({super.key, this.rows = 10});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      itemExtent: 76,
      itemBuilder: (context, index) => const _SkeletonRow(),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.md),
      child: Row(
        children: [
          ShimmerBox(width: 40, height: 40, borderRadius: 20),
          SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShimmerBox(width: 120, height: 12),
                SizedBox(height: AppSizes.sm),
                ShimmerBox(width: 180, height: 10),
                SizedBox(height: AppSizes.sm),
                ShimmerBox(width: 90, height: 9),
              ],
            ),
          ),
          SizedBox(width: AppSizes.sm),
          ShimmerBox(width: 58, height: 18, borderRadius: AppSizes.radiusPill),
        ],
      ),
    );
  }
}
