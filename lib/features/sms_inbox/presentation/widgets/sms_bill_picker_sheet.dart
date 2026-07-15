import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../bills/domain/bill.dart';
import '../../../bills/presentation/providers/bill_providers.dart';

/// "Which bill is this for?" picker shown before `PaymentFormSheet` when
/// converting an SMS into a Bill Payment — an SMS never names a specific
/// tracked bill, so the user picks one first.
class SmsBillPickerSheet extends ConsumerStatefulWidget {
  const SmsBillPickerSheet({super.key});

  static Future<Bill?> show(BuildContext context) {
    return showModalBottomSheet<Bill>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SmsBillPickerSheet(),
    );
  }

  @override
  ConsumerState<SmsBillPickerSheet> createState() => _SmsBillPickerSheetState();
}

class _SmsBillPickerSheetState extends ConsumerState<SmsBillPickerSheet> {
  String? _billId;

  @override
  Widget build(BuildContext context) {
    final bills = (ref.watch(billsStreamProvider).value ?? const <Bill>[])
        .where((b) => b.remainingAmount > 0)
        .toList();
    final selectedBill = bills.where((b) => b.id == _billId).firstOrNull;

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
          Text('Which bill is this for?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSizes.lg),
          DropdownButtonFormField<String>(
            initialValue: _billId,
            decoration: const InputDecoration(labelText: 'Bill'),
            items: [
              for (final bill in bills)
                DropdownMenuItem(
                  value: bill.id,
                  child: Text('${bill.name} · ${CurrencyFormatter.instance.format(bill.remainingAmount)} left'),
                ),
            ],
            onChanged: (value) => setState(() => _billId = value),
          ),
          const SizedBox(height: AppSizes.xl),
          PrimaryButton(
            label: 'Continue',
            onPressed: selectedBill == null ? null : () => Navigator.of(context).pop(selectedBill),
          ),
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    );
  }
}
