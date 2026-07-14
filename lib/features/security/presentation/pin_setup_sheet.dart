import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/services/security/app_lock_controller.dart';
import '../../../shared/widgets/inputs/pin_pad.dart';

/// Two-step "enter PIN, then confirm" bottom sheet used both for first-time
/// app-lock setup and for "Change PIN" in Settings.
class PinSetupSheet extends ConsumerStatefulWidget {
  const PinSetupSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const PinSetupSheet(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends ConsumerState<PinSetupSheet> {
  String _firstPin = '';
  String _input = '';
  bool _confirming = false;
  String? _error;

  Future<void> _onDigit(String digit) async {
    if (_input.length >= 6) return;
    setState(() {
      _input += digit;
      _error = null;
    });

    if (_input.length != 6) return;

    if (!_confirming) {
      setState(() {
        _firstPin = _input;
        _input = '';
        _confirming = true;
      });
      return;
    }

    if (_input == _firstPin) {
      await ref.read(appLockProvider.notifier).setPin(_firstPin);
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = 'PINs didn\'t match. Start again.';
        _firstPin = '';
        _input = '';
        _confirming = false;
      });
    }
  }

  void _onBackspace() {
    if (_input.isEmpty) return;
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _confirming ? 'Confirm your PIN' : 'Create a 6-digit PIN',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSizes.sm),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: AppSizes.lg),
            PinDotsIndicator(length: 6, filled: _input.length, hasError: _error != null),
            const SizedBox(height: AppSizes.xl),
            PinPad(onDigit: _onDigit, onBackspace: _onBackspace),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
