import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
import '../providers/pdf_import_providers.dart';
import '../providers/pdf_import_state.dart';

/// Prompts for a statement PDF's password and retries opening it —
/// `PdfImportController.submitPassword` never logs the attempt and never
/// echoes it back in an error message, and this dialog mirrors that: the
/// field is obscured, and nothing typed here is ever displayed elsewhere.
/// Stays open across a wrong-password retry (the controller returns to
/// [PdfImportStage.awaitingPassword] with `passwordError` set rather than
/// closing anything), and pops itself only once the state moves past
/// [PdfImportStage.awaitingPassword] (either extracted, or the user backs
/// out with the file left unset).
class PdfPasswordDialog extends ConsumerStatefulWidget {
  const PdfPasswordDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PdfPasswordDialog(),
    );
  }

  @override
  ConsumerState<PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends ConsumerState<PdfPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    await ref
        .read(pdfImportControllerProvider.notifier)
        .submitPassword(password);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PdfImportState>(pdfImportControllerProvider, (previous, next) {
      if (next.stage != PdfImportStage.awaitingPassword &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    final state = ref.watch(pdfImportControllerProvider);

    final hasError = state.passwordError != null;

    return PopScope(
      canPop: !_submitting,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FlowFiIconChip(
                    icon: Icons.lock_outline_rounded,
                    color: context.colors.primary,
                    size: 44,
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Text(
                      'Password protected PDF',
                      style: context.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Enter the password to open this statement. Nothing you '
                'type here is stored or shown anywhere else.',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              TextField(
                controller: _controller,
                obscureText: _obscure,
                autofocus: true,
                enabled: !_submitting,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: state.passwordError,
                  isDense: true,
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  enabledBorder: hasError
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusSm,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.expense,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Unlock'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
