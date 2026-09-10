import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
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

    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: const Text('Password protected PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the password to open this statement.'),
            const SizedBox(height: AppSizes.md),
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
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Unlock'),
          ),
        ],
      ),
    );
  }
}
