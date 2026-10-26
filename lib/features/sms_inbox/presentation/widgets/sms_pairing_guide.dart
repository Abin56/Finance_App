import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../providers/sms_auto_sync_providers.dart';
import 'sms_sync_visuals.dart';

/// The four beats of the existing external-camera pairing flow. FlowFi has no
/// in-app scanner: the phone's own Camera reads the Web QR and its link opens
/// FlowFi on the approval screen.
const smsPairingGuideBeats = <({String title, String body})>[
  (
    title: 'Open FlowFi Web',
    body: 'On a laptop, open Transaction Inbox and keep the QR on screen.',
  ),
  (title: 'Scan with Camera', body: "Scan the QR using your phone's Camera."),
  (
    title: 'Tap the link',
    body: 'Camera shows a FlowFi link — tap it to come back here.',
  ),
  (title: 'Approve', body: 'Check the request in FlowFi and tap Approve.'),
];

/// What the SMS Inbox shows instead of messages until this phone is paired:
/// the pairing guide plus the one thing to do next. The setup card above owns
/// the controls; this only points at them.
class SmsPairFirstEmptyState extends ConsumerWidget {
  const SmsPairFirstEmptyState({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(smsAutoSyncProvider).value;
    final textTheme = context.textTheme;
    final muted = smsSyncMuted(context);

    final smsGranted =
        status != null && status.receiveSmsGranted && status.readSmsGranted;
    final (IconData icon, String text, bool ready) = !smsGranted
        ? (Icons.arrow_upward_rounded, 'Next: allow SMS access above', false)
        : !status.isEffective
        ? (Icons.arrow_upward_rounded, 'Next: turn on Auto Sync above', false)
        : (
            Icons.laptop_mac_rounded,
            "You're ready — open FlowFi Web on a laptop to get the QR",
            true,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.lg,
        AppSizes.md,
        AppSizes.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: smsSyncMutedSurface(context),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                  child: Icon(
                    Icons.mark_email_unread_outlined,
                    size: 20,
                    color: muted,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pair with FlowFi Web to see your bank SMS here',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Messages stay hidden here until this phone is paired.',
                        style: textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const SmsPairingGuide(),
          const SizedBox(height: AppSizes.md),
          AnimatedSwitcher(
            duration: smsSyncMotion(context, 250),
            child: Container(
              key: ValueKey(text),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: ready
                    ? smsSyncAccentWash(context)
                    : smsSyncMutedSurface(context),
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: ready ? smsSyncAccentInk(context) : muted,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      text,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.open_in_new_rounded,
                    size: 13,
                    color: muted,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "You'll leave FlowFi for a moment to open Camera. The link brings you back.",
                    style: textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short looping picture of the pairing flow: Web QR → Camera → link →
/// Approve. A demonstration, not a status — it never shows a paired result.
/// Under "remove animations" it becomes a static scene plus a numbered list.
class SmsPairingGuide extends StatefulWidget {
  const SmsPairingGuide({super.key});

  @override
  State<SmsPairingGuide> createState() => _SmsPairingGuideState();
}

class _SmsPairingGuideState extends State<SmsPairingGuide>
    with SingleTickerProviderStateMixin {
  static const _beatMs = 2600;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _beatMs * smsPairingGuideBeats.length),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (smsSyncReduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _jumpTo(int beat) {
    _c.value = beat / smsPairingGuideBeats.length;
    if (!smsSyncReduceMotion(context)) _c.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = smsSyncReduceMotion(context);
    final textTheme = context.textTheme;
    final muted = smsSyncMuted(context);
    final n = smsPairingGuideBeats.length;

    return Semantics(
      label:
          'How pairing works: ${[for (var i = 0; i < n; i++) '${i + 1}. ${smsPairingGuideBeats[i].body}'].join(' ')}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          AppSizes.md,
          AppSizes.lg,
          AppSizes.md,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          border: Border.all(color: smsSyncBorder(context)),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final pos = reduce ? 1.5 : _c.value * n;
            final beat = pos.floor().clamp(0, n - 1);
            final t = reduce ? 0.5 : pos - beat;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'How pairing works',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                    ),
                    if (!reduce)
                      Text(
                        '${beat + 1} of $n',
                        style: textTheme.labelSmall?.copyWith(color: muted),
                      ),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                // Decorative and fixed-size: immune to text scaling.
                MediaQuery.withNoTextScaling(
                  child: SizedBox(
                    height: 124,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _Scene(beat: beat, t: t),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                if (reduce)
                  for (var i = 0; i < n; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSizes.xs),
                      child: _Caption(index: i, compact: true),
                    )
                else ...[
                  Row(
                    children: [
                      for (var i = 0; i < n; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: InkWell(
                            onTap: () => _jumpTo(i),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: _Segment(
                                fill: i < beat
                                    ? 1
                                    : i == beat
                                    ? t
                                    : 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Every caption is laid out; only the current one shows, so
                  // the card never changes height between beats.
                  Stack(
                    children: [
                      for (var i = 0; i < n; i++)
                        AnimatedOpacity(
                          opacity: i == beat ? 1 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: _Caption(index: i, compact: false),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: smsSyncBorder(context))),
            FractionallySizedBox(
              widthFactor: fill.clamp(0.0, 1.0),
              child: ColoredBox(color: smsSyncAccentInk(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.index, required this.compact});

  final int index;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final beat = smsPairingGuideBeats[index];
    final textTheme = context.textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: smsSyncAccentWash(context),
            shape: BoxShape.circle,
          ),
          child: Text(
            '${index + 1}',
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: smsSyncAccentInk(context),
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: compact
              ? Text(beat.body, style: textTheme.bodySmall)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      beat.title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      beat.body,
                      style: textTheme.bodySmall?.copyWith(
                        color: smsSyncMuted(context),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Scene: laptop with the Web QR, a phone running Camera, then FlowFi ──

class _Scene extends StatelessWidget {
  const _Scene({required this.beat, required this.t});

  final int beat;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Laptop(active: beat == 0),
        SizedBox(
          width: 44,
          child: _Beam(active: beat == 1, t: t),
        ),
        _Phone(beat: beat, t: t),
      ],
    );
  }
}

class _Laptop extends StatelessWidget {
  const _Laptop({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final border = smsSyncBorder(context);
    final muted = smsSyncMuted(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: smsSyncMotion(context, 250),
          width: 108,
          height: 72,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: smsSyncMutedSurface(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? smsSyncAccentInk(context) : border,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(width: 30, height: 3, color: border),
                ],
              ),
              const Spacer(),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const _MiniQr(size: 34),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        Container(
          width: 124,
          height: 5,
          decoration: BoxDecoration(
            color: border,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(3),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'FlowFi Web',
          style: context.textTheme.labelSmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// Three dots between laptop and phone that light up while Camera reads.
class _Beam extends StatelessWidget {
  const _Beam({required this.active, required this.t});

  final bool active;
  final double t;

  @override
  Widget build(BuildContext context) {
    final lit = active ? (t * 4).floor().clamp(0, 3) : -1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            AnimatedContainer(
              duration: smsSyncMotion(context, 180),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < lit
                    ? smsSyncAccentInk(context)
                    : smsSyncBorder(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone({required this.beat, required this.t});

  final int beat;
  final double t;

  @override
  Widget build(BuildContext context) {
    final active = beat > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: smsSyncMotion(context, 250),
          width: 58,
          height: 98,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.nearBlack,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: active ? smsSyncAccentInk(context) : AppColors.nearBlack,
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AnimatedSwitcher(
              duration: smsSyncMotion(context, 260),
              child: KeyedSubtree(
                key: ValueKey(beat == 1 || beat == 2 ? 'camera' : '$beat'),
                child: switch (beat) {
                  0 => const _PhoneIdle(),
                  1 || 2 => _CameraView(t: t, showLink: beat == 2),
                  _ => _ApproveView(t: t),
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your phone',
          style: context.textTheme.labelSmall?.copyWith(
            color: smsSyncMuted(context),
          ),
        ),
      ],
    );
  }
}

class _PhoneIdle extends StatelessWidget {
  const _PhoneIdle();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.raisedDark,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.photo_camera_rounded,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Camera',
            style: TextStyle(
              fontSize: 7,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraView extends StatelessWidget {
  const _CameraView({required this.t, required this.showLink});

  final double t;
  final bool showLink;

  @override
  Widget build(BuildContext context) {
    const lime = AppColors.lime;
    final reduce = smsSyncReduceMotion(context);
    // Link slides up in the first half of its beat; the "tap" follows.
    final rise = Curves.easeOutCubic.transform((t * 2).clamp(0.0, 1.0));
    final tap = ((t - 0.55) / 0.35).clamp(0.0, 1.0);
    return Container(
      color: const Color(0xFF2B2C29),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Viewfinder brackets around the code.
          const SizedBox(
            width: 38,
            height: 38,
            child: CustomPaint(painter: _BracketPainter(color: lime)),
          ),
          Container(
            padding: const EdgeInsets.all(2),
            color: Colors.white,
            child: const _MiniQr(size: 24),
          ),
          if (!showLink && !reduce)
            Positioned(
              top: 26 + 36 * t,
              child: Container(
                width: 34,
                height: 1.5,
                decoration: BoxDecoration(
                  color: lime,
                  boxShadow: [
                    BoxShadow(
                      color: lime.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          if (showLink)
            Positioned(
              bottom: 8 + 6 * rise - 6,
              child: Opacity(
                opacity: rise,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.link_rounded,
                            size: 8,
                            color: AppColors.onLime,
                          ),
                          SizedBox(width: 2),
                          Text(
                            'FlowFi',
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onLime,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tap > 0)
                      Container(
                        width: 10 + 14 * tap,
                        height: 10 + 14 * tap,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: lime.withValues(alpha: 0.45 * (1 - tap)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApproveView extends StatelessWidget {
  const _ApproveView({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final pressed = t > 0.55 || smsSyncReduceMotion(context);
    return Container(
      color: AppColors.darkSurface,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 7),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.lime,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 3),
              Container(
                width: 18,
                height: 3,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ],
          ),
          const Spacer(),
          const Icon(
            Icons.phonelink_lock_rounded,
            size: 16,
            color: AppColors.lime,
          ),
          const SizedBox(height: 4),
          Container(
            width: 34,
            height: 3,
            color: Colors.white.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 3),
          Container(
            width: 26,
            height: 3,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const Spacer(),
          AnimatedContainer(
            duration: smsSyncMotion(context, 160),
            height: 15,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.lime,
              borderRadius: BorderRadius.circular(7),
              boxShadow: pressed
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.lime.withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ],
            ),
            child: pressed
                ? const Icon(
                    Icons.check_rounded,
                    size: 10,
                    color: AppColors.onLime,
                  )
                : const Text(
                    'Approve',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onLime,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A fixed, fictional QR-like glyph (finder squares + a static module
/// pattern). It encodes nothing and is never scannable.
class _MiniQr extends StatelessWidget {
  const _MiniQr({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _MiniQrPainter()),
    );
  }
}

class _MiniQrPainter extends CustomPainter {
  const _MiniQrPainter();

  // 9×9 grid; 1 = dark module. Corners are finder squares drawn separately.
  static const _modules = [
    '000000000',
    '000010100',
    '000101000',
    '010110110',
    '101001011',
    '011011100',
    '000010110',
    '000101011',
    '000011010',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 9;
    final dark = Paint()..color = const Color(0xFF151715);
    final light = Paint()..color = Colors.white;
    void finder(double x, double y) {
      canvas.drawRect(Rect.fromLTWH(x, y, cell * 3, cell * 3), dark);
      canvas.drawRect(
        Rect.fromLTWH(x + cell * 0.6, y + cell * 0.6, cell * 1.8, cell * 1.8),
        light,
      );
      canvas.drawRect(Rect.fromLTWH(x + cell, y + cell, cell, cell), dark);
    }

    finder(0, 0);
    finder(cell * 6, 0);
    finder(0, cell * 6);
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final inFinder = (r < 3 && (c < 3 || c > 5)) || (r > 5 && c < 3);
        if (inFinder || _modules[r][c] != '1') continue;
        canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BracketPainter extends CustomPainter {
  const _BracketPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 8.0;
    final w = size.width, h = size.height;
    canvas
      ..drawLine(Offset.zero, const Offset(l, 0), p)
      ..drawLine(Offset.zero, const Offset(0, l), p)
      ..drawLine(Offset(w, 0), Offset(w - l, 0), p)
      ..drawLine(Offset(w, 0), Offset(w, l), p)
      ..drawLine(Offset(0, h), Offset(l, h), p)
      ..drawLine(Offset(0, h), Offset(0, h - l), p)
      ..drawLine(Offset(w, h), Offset(w - l, h), p)
      ..drawLine(Offset(w, h), Offset(w, h - l), p);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter oldDelegate) =>
      oldDelegate.color != color;
}
