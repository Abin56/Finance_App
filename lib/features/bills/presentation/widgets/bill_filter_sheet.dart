import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../domain/bill_status.dart';
import 'bill_filter.dart';

/// Bottom sheet for narrowing the Bills list by status, category, account,
/// and date range — mirrors `TransactionFilterSheet`.
class BillFilterSheet extends ConsumerStatefulWidget {
  const BillFilterSheet({super.key, required this.initialFilter});

  final BillFilter initialFilter;

  static Future<BillFilter?> show(BuildContext context, BillFilter current) {
    return showModalBottomSheet<BillFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BillFilterSheet(initialFilter: current),
    );
  }

  @override
  ConsumerState<BillFilterSheet> createState() => _BillFilterSheetState();
}

class _BillFilterSheetState extends ConsumerState<BillFilterSheet> {
  late BillStatus? _status = widget.initialFilter.status;
  late String? _categoryId = widget.initialFilter.categoryId;
  late String? _accountId = widget.initialFilter.accountId;
  late DateTime? _startDate = widget.initialFilter.startDate;
  late DateTime? _endDate = widget.initialFilter.endDate;

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked.start;
      _endDate = picked.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                TextButton(
                  onPressed: () => setState(() {
                    _status = null;
                    _categoryId = null;
                    _accountId = null;
                    _startDate = null;
                    _endDate = null;
                  }),
                  child: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            DropdownButtonFormField<BillStatus?>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final status in BillStatus.values)
                  DropdownMenuItem(value: status, child: Text(status.label)),
              ],
              onChanged: (value) => setState(() => _status = value),
            ),
            const SizedBox(height: AppSizes.md),
            accountsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Could not load accounts: $error'),
              data: (accounts) => DropdownButtonFormField<String?>(
                initialValue: accounts.any((a) => a.id == _accountId) ? _accountId : null,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final account in accounts)
                    DropdownMenuItem(value: account.id, child: Text(account.name)),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            DropdownButtonFormField<String?>(
              initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final category in categories)
                  DropdownMenuItem(value: category.id, child: Text(category.name)),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: AppSizes.md),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_outlined, size: AppSizes.iconSm),
              label: Text(
                _startDate != null && _endDate != null
                    ? '${_startDate!.shortDate} - ${_endDate!.shortDate}'
                    : 'Due date range',
              ),
            ),
            const SizedBox(height: AppSizes.xl),
            PrimaryButton(
              label: 'Apply filters',
              onPressed: () => Navigator.of(context).pop(
                BillFilter(
                  status: _status,
                  categoryId: _categoryId,
                  accountId: _accountId,
                  startDate: _startDate,
                  endDate: _endDate,
                ),
              ),
            ),
            const SizedBox(height: AppSizes.sm),
          ],
        ),
      ),
    );
  }
}
