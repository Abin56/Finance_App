import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../domain/transaction_type.dart';
import 'transaction_filter.dart';

/// Bottom sheet for narrowing the History list by type, account, category,
/// and date range. Returns the chosen [TransactionFilter] via the
/// [Navigator] pop result; `null` selections mean "no constraint".
class TransactionFilterSheet extends ConsumerStatefulWidget {
  const TransactionFilterSheet({super.key, required this.initialFilter});

  final TransactionFilter initialFilter;

  static Future<TransactionFilter?> show(BuildContext context, TransactionFilter current) {
    return showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TransactionFilterSheet(initialFilter: current),
    );
  }

  @override
  ConsumerState<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends ConsumerState<TransactionFilterSheet> {
  late TransactionType? _type = widget.initialFilter.type;
  late String? _accountId = widget.initialFilter.accountId;
  late String? _categoryId = widget.initialFilter.categoryId;
  late DateTime? _startDate = widget.initialFilter.startDate;
  late DateTime? _endDate = widget.initialFilter.endDate;
  late bool _includeExcluded = widget.initialFilter.includeExcluded;
  late bool _filterByAccountingMonth = widget.initialFilter.filterByAccountingMonth;

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
    final categories = _type == null
        ? ref.watch(categoriesStreamProvider).value ?? const []
        : ref.watch(categoriesForTypeProvider(_type!));

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
                    _type = null;
                    _accountId = null;
                    _categoryId = null;
                    _startDate = null;
                    _endDate = null;
                    _includeExcluded = true;
                    _filterByAccountingMonth = false;
                  }),
                  child: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            DropdownButtonFormField<TransactionType?>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final type in TransactionType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) => setState(() {
                _type = value;
                if (_categoryId != null && !categories.any((c) => c.id == _categoryId)) {
                  _categoryId = null;
                }
              }),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include Excluded Transactions'),
              subtitle: const Text('Turn off to hide transactions marked "Exclude from Financial Calculations".'),
              value: _includeExcluded,
              onChanged: (value) => setState(() => _includeExcluded = value),
            ),
            const SizedBox(height: AppSizes.sm),
            Text('Filter dates by', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSizes.xs),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Transaction Date')),
                ButtonSegment(value: true, label: Text('Accounting Month')),
              ],
              selected: {_filterByAccountingMonth},
              onSelectionChanged: (selection) => setState(() => _filterByAccountingMonth = selection.first),
            ),
            const SizedBox(height: AppSizes.md),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_outlined, size: AppSizes.iconSm),
              label: Text(
                _startDate != null && _endDate != null
                    ? '${_startDate!.shortDate} - ${_endDate!.shortDate}'
                    : 'Date range',
              ),
            ),
            const SizedBox(height: AppSizes.xl),
            PrimaryButton(
              label: 'Apply filters',
              onPressed: () => Navigator.of(context).pop(
                TransactionFilter(
                  type: _type,
                  accountId: _accountId,
                  categoryId: _categoryId,
                  startDate: _startDate,
                  endDate: _endDate,
                  includeExcluded: _includeExcluded,
                  filterByAccountingMonth: _filterByAccountingMonth,
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
