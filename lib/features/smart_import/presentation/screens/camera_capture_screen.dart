import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/camera_capture_outcome.dart';
import '../providers/smart_import_providers.dart';

/// Camera as a second input source for Smart Import, alongside the existing
/// gallery/screenshot picker. This screen's only job is to hand a
/// user-confirmed image to [SmartImportController.confirmCapturedImage] and
/// kick off the *same* [SmartImportController.processImages] pipeline the
/// gallery flow already uses — no separate OCR, extraction, duplicate
/// detection, or review screen exists for a camera-sourced image.
class CameraCaptureScreen extends ConsumerStatefulWidget {
  const CameraCaptureScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
  }

  @override
  ConsumerState<CameraCaptureScreen> createState() =>
      _CameraCaptureScreenState();
}

enum _CaptureScreenState {
  capturing,
  preview,
  permissionDenied,
  permissionPermanentlyDenied,
  unavailable,
}

class _CameraCaptureScreenState extends ConsumerState<CameraCaptureScreen> {
  _CaptureScreenState _screenState = _CaptureScreenState.capturing;
  File? _capturedImage;

  /// Set right before popping via "Use Photo" — [dispose] uses this to tell
  /// "the image was confirmed" apart from every other way this screen can
  /// go away (back button, retake, system back gesture), so a capture the
  /// user didn't explicitly keep is always cleaned up in exactly one place.
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _capture();
  }

  @override
  void dispose() {
    final leftoverCapture = _capturedImage;
    if (!_confirmed && leftoverCapture != null) {
      ref
          .read(smartImportControllerProvider.notifier)
          .discardCapturedImage(leftoverCapture);
    }
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() => _screenState = _CaptureScreenState.capturing);

    final outcome = await ref
        .read(smartImportControllerProvider.notifier)
        .captureFromCamera();
    if (!mounted) return;

    switch (outcome.status) {
      case CameraCaptureStatus.success:
        setState(() {
          _capturedImage = outcome.file;
          _screenState = _CaptureScreenState.preview;
        });
      case CameraCaptureStatus.cancelled:
        // The user backed out of the system camera itself — return to
        // Smart Import quietly, exactly as cancelling the gallery picker
        // already does.
        Navigator.of(context).pop();
      case CameraCaptureStatus.permissionDenied:
        setState(() => _screenState = _CaptureScreenState.permissionDenied);
      case CameraCaptureStatus.permissionPermanentlyDenied:
        setState(
          () => _screenState = _CaptureScreenState.permissionPermanentlyDenied,
        );
      case CameraCaptureStatus.unavailable:
        setState(() => _screenState = _CaptureScreenState.unavailable);
    }
  }

  void _retake() {
    final old = _capturedImage;
    setState(() {
      _capturedImage = null;
      _screenState = _CaptureScreenState.capturing;
    });
    if (old != null) {
      ref
          .read(smartImportControllerProvider.notifier)
          .discardCapturedImage(old);
    }
    _capture();
  }

  void _usePhoto() {
    final file = _capturedImage;
    if (file == null) return;
    _confirmed = true;

    final controller = ref.read(smartImportControllerProvider.notifier);
    controller.confirmCapturedImage(file);
    // Fire-and-forget: `processImages()` sets `stage: processing`
    // synchronously before its first `await`, so by the time `pop()` below
    // reveals Smart Import's entry screen underneath, it already renders
    // the existing "Reading screenshot…" progress view — the same one the
    // gallery flow uses — rather than a flash of the picker view.
    controller.processImages();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan with Camera')),
      body: switch (_screenState) {
        _CaptureScreenState.capturing => const Center(
          child: CircularProgressIndicator(),
        ),
        _CaptureScreenState.preview => _PreviewView(
          file: _capturedImage!,
          onRetake: _retake,
          onUsePhoto: _usePhoto,
        ),
        _CaptureScreenState.permissionDenied => _MessageView(
          icon: Icons.no_photography_outlined,
          title: 'Camera permission is required',
          message: 'Allow camera access to scan transactions.',
          primaryLabel: 'Allow Camera Access',
          onPrimary: _capture,
        ),
        _CaptureScreenState.permissionPermanentlyDenied => _MessageView(
          icon: Icons.no_photography_outlined,
          title: 'Camera permission is required',
          message:
              "FlowFi doesn't have permission to use the camera. "
              'Enable it in your device settings to scan transactions.',
          primaryLabel: 'Open Settings',
          onPrimary: () =>
              ref.read(cameraPermissionServiceProvider).openSettings(),
        ),
        _CaptureScreenState.unavailable => _MessageView(
          icon: Icons.videocam_off_outlined,
          title: 'Camera unavailable',
          message: "Camera isn't available on this device.",
          primaryLabel: 'Go Back',
          onPrimary: () => Navigator.of(context).pop(),
        ),
      },
    );
  }
}

class _PreviewView extends StatelessWidget {
  const _PreviewView({
    required this.file,
    required this.onRetake,
    required this.onUsePhoto,
  });

  final File file;
  final VoidCallback onRetake;
  final VoidCallback onUsePhoto;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRetake,
                    icon: const Icon(Icons.replay_outlined),
                    label: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: PrimaryButton(
                    label: 'Use Photo',
                    icon: Icons.check_rounded,
                    onPressed: onUsePhoto,
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

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppSizes.iconXl,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(height: AppSizes.lg),
            Text(
              title,
              style: context.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSizes.sm),
            Text(
              message,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSizes.xl),
            PrimaryButton(label: primaryLabel, onPressed: onPrimary),
          ],
        ),
      ),
    );
  }
}
