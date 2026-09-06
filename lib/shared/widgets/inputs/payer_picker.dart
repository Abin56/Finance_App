import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/models/payer_source.dart';
import '../../../features/people/presentation/providers/people_providers.dart';
import '../../../features/people/presentation/widgets/person_form_sheet.dart';

/// Sentinel dropdown value for the "Add new person" shortcut — distinct from
/// any real person id, so selecting it can be intercepted before it's ever
/// treated as a real person id.
const _addNewPersonValue = '__add_new_person__';

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
              const DropdownMenuItem(
                value: _addNewPersonValue,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18),
                    SizedBox(width: AppSizes.xs),
                    Text('Add new person'),
                  ],
                ),
              ),
            ],
            onChanged: (value) async {
              if (value == _addNewPersonValue) {
                final newPersonId = await PersonFormSheet.show(context);
                if (newPersonId != null) onPersonChanged(newPersonId);
                return;
              }
              onPersonChanged(value);
            },
            validator: (value) => value == null ? 'Choose who paid' : null,
          ),
        ],
      ],
    );
  }
}
