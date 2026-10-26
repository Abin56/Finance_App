import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';
import 'shimmer_box.dart';

/// Whether a section's data is ready to render — derived from the
/// [AsyncValue]s of the streams it reads, so a still-loading stream is never
/// mistaken for "no data" (the `.value ?? const []` pattern renders ₹0 / "No
/// accounts yet" while Firestore is still answering).
enum SectionLoadStatus { loading, error, ready }

@immutable
class SectionLoad {
  const SectionLoad._(this.status, [this.error]);

  const SectionLoad.ready() : this._(SectionLoadStatus.ready);

  final SectionLoadStatus status;
  final Object? error;

  bool get isLoading => status == SectionLoadStatus.loading;
  bool get hasError => status == SectionLoadStatus.error;
  bool get isReady => status == SectionLoadStatus.ready;

  /// Error wins only when there is nothing to show (a stream that errored
  /// after delivering data keeps showing that data); otherwise any source
  /// still waiting for its first value means loading.
  static SectionLoad of(Iterable<AsyncValue<Object?>> sources) {
    for (final s in sources) {
      if (s.hasError && !s.hasValue) {
        return SectionLoad._(SectionLoadStatus.error, s.error);
      }
    }
    for (final s in sources) {
      if (!s.hasValue) return const SectionLoad._(SectionLoadStatus.loading);
    }
    return const SectionLoad.ready();
  }
}

/// Placeholder rows shaped like a typical list section — shown while
/// [SectionLoad.isLoading].
class SectionSkeleton extends StatelessWidget {
  const SectionSkeleton({super.key, this.rows = 3, this.leadingHeight = 28});

  final int rows;

  /// Height of the first, wider block (a headline figure); 0 to omit it.
  final double leadingHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leadingHeight > 0) ...[
            ShimmerBox(width: 140, height: leadingHeight),
            const SizedBox(height: AppSizes.md),
          ],
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const SizedBox(height: AppSizes.sm),
            Row(
              children: [
                const ShimmerBox(
                  width: 28,
                  height: 28,
                  borderRadius: AppSizes.radiusXs,
                ),
                const SizedBox(width: AppSizes.sm),
                const Expanded(child: ShimmerBox(height: 12)),
                const SizedBox(width: AppSizes.xl),
                const ShimmerBox(width: 56, height: 12),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact, honest failure row: what failed, plus Retry. Never shows a
/// placeholder figure in place of the real one.
class SectionErrorRow extends StatelessWidget {
  const SectionErrorRow({
    super.key,
    required this.message,
    this.onRetry,
    this.onHeroSurface = false,
  });

  final String message;
  final VoidCallback? onRetry;

  /// Use the hero (near-black) foreground tokens instead of the surface ones.
  final bool onHeroSurface;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = onHeroSurface
        ? context.flowfi.onHeroSurface
        : colors.onSurface;
    final muted = onHeroSurface
        ? context.flowfi.onHeroSurfaceMuted
        : colors.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: AppSizes.iconSm, color: muted),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Text(
            message,
            style: context.textTheme.bodySmall?.copyWith(color: foreground),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: foreground,
              minimumSize: const Size(48, 40),
            ),
            child: const Text('Retry'),
          ),
      ],
    );
  }
}
