import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../domain/statement.dart';
import '../providers/credit_card_providers.dart';

/// Bottom sheet for logging (or correcting) a statement's manually-entered
/// interest charged / late fee — the only fields a [Statement] supports
/// editing after generation, since this app has no interest/late-fee
/// calculation engine (see `StatementRepository.editStatement`'s dartdoc).
/// Leaving a field blank clears it rather than setting it to 0, so a
/// statement with no fees logged simply omits them from the UI everywhere
/// else instead of showing a misleading "₹0".
class StatementFeesSheet extends ConsumerStatefulWidget {
  const StatementFeesSheet({super.key, required this.cardId, required this.statement});

  final String cardId;
  final Statement statement;

  static Future<void> show(BuildContext context, {required String cardId, required Statement statement}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatementFeesSheet(cardId: cardId, statement: statement),
    );
  }

  @override
  ConsumerState<StatementFeesSheet> createState() => _StatementFeesSheetState();
}

class _StatementFeesSheetState extends ConsumerState<StatementFeesSheet> {
  late final _interestController = TextEditingController(
    text: widget.statement.interestCharged?.toStringAsFixed(2) ?? '',
  );
  late final _lateFeeController = TextEditingController(
    text: widget.statement.lateFee?.toStringAsFixed(2) ?? '',
  );
  bool _isSaving = false;

  @override
  void dispose() {
    _interestController.dispose();
    _lateFeeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(statementRepositoryProvider(widget.cardId));
      final interestText = _interestController.text.trim();
      final lateFeeText = _lateFeeController.text.trim();
      await repository.editStatement(
        widget.statement,
        interestCharged: interestText.isEmpty ? null : double.tryParse(interestText),
        clearInterestCharged: interestText.isEmpty,
        lateFee: lateFeeText.isEmpty ? null : double.tryParse(lateFeeText),
        clearLateFee: lateFeeText.isEmpty,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Interest & late fees', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSizes.xs),
          Text(
            "Log any interest or late fee this statement charged — leave blank if it didn't.",
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSizes.lg),
          TextField(
            controller: _interestController,
            decoration: const InputDecoration(labelText: 'Interest charged (optional)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _lateFeeController,
            decoration: const InputDecoration(labelText: 'Late fee (optional)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: AppSizes.xl),
          PrimaryButton(label: 'Save', isLoading: _isSaving, onPressed: _save),
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    );
  }
}
