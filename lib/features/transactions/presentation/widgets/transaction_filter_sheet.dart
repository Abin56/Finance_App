import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
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
    final creditCards = ref.watch(creditCardsStreamProvider).value ?? const [];
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
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppClay.primaryGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: AppClay.glow(AppClay.primary),
                  ),
                  child: const Icon(Icons.tune_rounded, size: AppSizes.iconSm, color: Colors.white),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Filters', style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        'Narrow down your history',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ),
                ),
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
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            _ClayDropdownShell(
              icon: Icons.swap_horiz_rounded,
              child: DropdownButtonFormField<TransactionType?>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
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
            ),
            const SizedBox(height: AppSizes.md),
            accountsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Could not load accounts: $error'),
              data: (accounts) => _ClayDropdownShell(
                icon: Icons.account_balance_wallet_outlined,
                child: DropdownButtonFormField<String?>(
                  initialValue: accounts.any((a) => a.id == _accountId) ? _accountId : null,
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final account in accounts)
                      DropdownMenuItem(value: account.id, child: Text(accountPickerLabel(account, creditCards))),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            _ClayDropdownShell(
              icon: Icons.label_outline_rounded,
              child: DropdownButtonFormField<String?>(
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final category in categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Container(
              decoration: BoxDecoration(
                color: AppClay.card(context),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                boxShadow: AppClay.nested(context),
              ),
              child: SwitchListTile(
                title: const Text('Include Excluded Transactions'),
                subtitle: const Text('Turn off to hide transactions marked "Exclude from Financial Calculations".'),
                value: _includeExcluded,
                onChanged: (value) => setState(() => _includeExcluded = value),
                activeThumbColor: AppClay.primary,
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Row(
              children: [
                Icon(Icons.event_repeat_rounded, size: AppSizes.iconSm, color: AppClay.primaryAccent(context)),
                const SizedBox(width: AppSizes.xs),
                Text('Filter dates by', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: AppSizes.xs),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Transaction Date')),
                ButtonSegment(value: true, label: Text('Accounting Month')),
              ],
              selected: {_filterByAccountingMonth},
              onSelectionChanged: (selection) => setState(() => _filterByAccountingMonth = selection.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppClay.primaryAccent(context),
                selectedForegroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Container(
              decoration: BoxDecoration(
                color: AppClay.card(context),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                boxShadow: AppClay.nested(context),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _pickDateRange,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
                    child: Row(
                      children: [
                        Icon(Icons.date_range_outlined, size: AppSizes.iconSm, color: AppClay.primaryAccent(context)),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: Text(
                            _startDate != null && _endDate != null
                                ? '${_startDate!.shortDate} - ${_endDate!.shortDate}'
                                : 'Date range',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                ),
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

/// Wraps a dropdown field in the same soft floating-card look as the
/// "Include Excluded Transactions" toggle and the date-range row below it,
/// instead of the default Material filled-box input style — the dropdown's
/// own `InputDecoration` is set `filled: false`/borderless by the caller so
/// this shell's card is the only visible surface, not a box-within-a-box.
class _ClayDropdownShell extends StatelessWidget {
  const _ClayDropdownShell({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppClay.card(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        boxShadow: AppClay.nested(context),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(gradient: AppClay.iconChipGradient(AppClay.primary), shape: BoxShape.circle),
            child: Icon(icon, size: AppSizes.iconSm, color: AppClay.primary),
          ),
          const SizedBox(width: AppSizes.xs),
          Expanded(child: child),
        ],
      ),
    );
  }
}
