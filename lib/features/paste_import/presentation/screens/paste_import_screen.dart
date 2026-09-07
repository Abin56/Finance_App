import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../providers/paste_import_providers.dart';
import '../providers/paste_import_state.dart';
import 'paste_transaction_review_screen.dart';

const _examplePasteText = '05 Sep SWIGGY 420 DR\n05 Sep AMAZON 1299 DR\n06 Sep UBER 185.50 DR';

/// Copy/Paste Import's entry screen — the user pastes transaction text
/// copied from a bank app, UPI app, SMS, email, or banking website, then
/// hands off to text extraction. Reached from `showAddEntryMenu`'s "Paste
/// Transactions" option, and optionally from a specific account's own screen
/// (in which case that account is preselected once the review screen opens).
/// A sibling of `SmartImportScreen` (Screenshot import's entry screen) —
/// same session-reset-on-open and stage-driven navigation pattern, applied to
/// a text field instead of an image picker.
class PasteImportScreen extends ConsumerStatefulWidget {
  const PasteImportScreen({super.key, this.initialAccountId});

  final String? initialAccountId;

  static Future<void> show(BuildContext context, {String? initialAccountId}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PasteImportScreen(initialAccountId: initialAccountId),
      ),
    );
  }

  @override
  ConsumerState<PasteImportScreen> createState() => _PasteImportScreenState();
}

class _PasteImportScreenState extends ConsumerState<PasteImportScreen> {
  late final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Reset any leftover state from a previous session before this screen
    // starts contributing to it, then apply the account preselection.
    Future.microtask(() {
      final controller = ref.read(pasteImportControllerProvider.notifier);
      controller.reset();
      controller.preselectAccount(widget.initialAccountId);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PasteImportState>(pasteImportControllerProvider, (previous, next) {
      if (next.pastedText != _textController.text) {
        _textController.value = _textController.value.copyWith(
          text: next.pastedText,
          selection: TextSelection.collapsed(offset: next.pastedText.length),
        );
      }

      final enteredReview = previous?.stage != PasteImportStage.reviewing &&
          next.stage == PasteImportStage.reviewing;
      if (enteredReview) {
        Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const PasteTransactionReviewScreen()),
        );
      }

      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    final state = ref.watch(pasteImportControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Paste Transactions')),
      body: state.stage == PasteImportStage.processing
          ? const _AnalyzingView()
          : _PasteTextView(state: state, textController: _textController),
    );
  }
}

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSizes.lg),
          Text('Analyzing text…', style: context.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PasteTextView extends ConsumerWidget {
  const _PasteTextView({required this.state, required this.textController});

  final PasteImportState state;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pasteImportControllerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste transactions', style: context.textTheme.titleMedium),
            const SizedBox(height: AppSizes.xs),
            Text(
              'Paste copied transaction information from your bank, UPI, or wallet '
              'app, an SMS, or an email — FlowFi will pull out the transactions for '
              'you to review. Nothing is saved until you confirm.',
              style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSizes.lg),
            Expanded(
              child: TextField(
                controller: textController,
                onChanged: controller.setText,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Paste copied transaction text here…\n\n'
                      'Example:\n$_examplePasteText',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Paste from clipboard'),
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                OutlinedButton.icon(
                  onPressed: state.pastedText.isEmpty
                      ? null
                      : () {
                          textController.clear();
                          controller.clearText();
                        },
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            PrimaryButton(
              label: 'Analyze',
              onPressed: state.pastedText.trim().isEmpty ? null : controller.analyze,
            ),
          ],
        ),
      ),
    );
  }
}
