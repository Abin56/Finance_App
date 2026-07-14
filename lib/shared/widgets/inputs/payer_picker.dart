import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/models/payer_source.dart';
import '../../../features/people/presentation/providers/people_providers.dart';

/// "You" / "Someone else paid this" toggle, reused by every payment sheet
/// (EMI, Loan, Bill) that lets a payment be recorded on someone else's
/// behalf. When "Someone else paid this" is selected, shows a required
/// Person dropdown (from [peopleStreamProvider]) so the sheet can build a
/// [PayerSource.person] to pass to `PaymentAttributionService.apply`.
///
/// Plain language only, per this app's UX rule — no "payer"/"third party".
class PayerPicker extends ConsumerWidget {
  const PayerPicker({
    super.key,
    required this.isSomeoneElse,
    required this.onModeChanged,
    required this.selectedPersonId,
    required this.onPersonChanged,
  });

  /// False = "You" (the default, [PayerSource.self]); true = "Someone else
  /// paid this" (requires [selectedPersonId] to build [PayerSource.person]).
  final bool isSomeoneElse;
  final ValueChanged<bool> onModeChanged;

  final String? selectedPersonId;
  final ValueChanged<String?> onPersonChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleStreamProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who paid this?', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSizes.sm),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('You')),
            ButtonSegment(value: true, label: Text('Someone else paid this')),
          ],
          selected: {isSomeoneElse},
          onSelectionChanged: (selection) => onModeChanged(selection.first),
        ),
        if (isSomeoneElse) ...[
          const SizedBox(height: AppSizes.md),
          DropdownButtonFormField<String>(
            initialValue: selectedPersonId,
            decoration: const InputDecoration(labelText: 'Who paid?'),
            items: [
              for (final person in people) DropdownMenuItem(value: person.id, child: Text(person.name)),
            ],
            onChanged: onPersonChanged,
            validator: (value) => value == null ? 'Choose who paid' : null,
          ),
        ],
      ],
    );
  }
}
