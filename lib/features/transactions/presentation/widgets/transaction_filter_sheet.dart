import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/dialogs/anchored_sort_menu.dart';
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

  final _typeFieldKey = GlobalKey();
  final _accountFieldKey = GlobalKey();
  final _categoryFieldKey = GlobalKey();

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
    final selectedCategory =
        categories.any((c) => c.id == _categoryId) ? categories.firstWhere((c) => c.id == _categoryId) : null;

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
            _FilterPickerField(
              fieldKey: _typeFieldKey,
              icon: Icons.swap_horiz_rounded,
              label: 'Type',
              value: _type?.label ?? 'All',
              onTap: () async {
                final result = await showAnchoredSortMenu<({TransactionType? value})>(
                  context: context,
                  anchorKey: _typeFieldKey,
                  selectedValue: (value: _type),
                  options: [
                    const SortMenuOption(value: (value: null), icon: Icons.apps_rounded, label: 'All'),
                    for (final type in TransactionType.values)
                      SortMenuOption(value: (value: type), icon: type.icon, label: type.label),
                  ],
                );
                if (result != null) {
                  setState(() {
                    _type = result.value;
                    if (_categoryId != null && !categories.any((c) => c.id == _categoryId)) {
                      _categoryId = null;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: AppSizes.md),
            accountsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Could not load accounts: $error'),
              data: (accounts) => _FilterPickerField(
                fieldKey: _accountFieldKey,
                icon: Icons.account_balance_wallet_outlined,
                label: 'Account',
                value: accounts.any((a) => a.id == _accountId)
                    ? accountPickerLabel(accounts.firstWhere((a) => a.id == _accountId), creditCards)
                    : 'All',
                onTap: () async {
                  final result = await showAnchoredSortMenu<({String? value})>(
                    context: context,
                    anchorKey: _accountFieldKey,
                    selectedValue: (value: accounts.any((a) => a.id == _accountId) ? _accountId : null),
                    options: [
                      const SortMenuOption(value: (value: null), icon: Icons.apps_rounded, label: 'All'),
                      for (final account in accounts)
                        SortMenuOption(
                          value: (value: account.id),
                          icon: Icons.account_balance_wallet_outlined,
                          label: accountPickerLabel(account, creditCards),
                        ),
                    ],
                  );
                  if (result != null) setState(() => _accountId = result.value);
                },
              ),
            ),
            const SizedBox(height: AppSizes.md),
            _FilterPickerField(
              fieldKey: _categoryFieldKey,
              icon: selectedCategory?.icon ?? Icons.label_outline_rounded,
              iconColor: selectedCategory != null ? Color(selectedCategory.colorValue) : null,
              label: 'Category',
              value: selectedCategory?.name ?? 'All',
              onTap: () async {
                final result = await showAnchoredSortMenu<({String? value})>(
                  context: context,
                  anchorKey: _categoryFieldKey,
                  selectedValue: (value: categories.any((c) => c.id == _categoryId) ? _categoryId : null),
                  options: [
                    const SortMenuOption(value: (value: null), icon: Icons.apps_rounded, label: 'All'),
                    for (final category in categories)
                      SortMenuOption(
                        value: (value: category.id),
                        icon: category.icon,
                        label: category.name,
                        color: Color(category.colorValue),
                      ),
                  ],
                );
                if (result != null) setState(() => _categoryId = result.value);
              },
            ),
            const SizedBox(height: AppSizes.md),
            Container(
              decoration: BoxDecoration(
                color: AppClay.card(context),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                boxShadow: AppClay.nested(context),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  title: const Text('Include Excluded Transactions'),
                  subtitle: const Text('Turn off to hide transactions marked "Exclude from Financial Calculations".'),
                  value: _includeExcluded,
                  onChanged: (value) => setState(() => _includeExcluded = value),
                  activeThumbColor: AppClay.primary,
                ),
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

/// A tappable field styled like the "Include Excluded Transactions" toggle
/// and the date-range row — icon chip, small label, current value, and a
/// chevron — that opens a compact [showAnchoredSortMenu] dropdown anchored
/// to itself instead of a full-size default `DropdownButtonFormField` popup
/// (whose rows can't shrink below Material's accessibility-minimum height).
class _FilterPickerField extends StatelessWidget {
  const _FilterPickerField({
    required this.fieldKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.iconColor,
  });

  final GlobalKey fieldKey;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// Overrides the icon chip's color — e.g. a selected category's own
  /// color. Null falls back to the brand accent.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = iconColor ?? AppClay.primary;
    return Container(
      key: fieldKey,
      decoration: BoxDecoration(
        color: AppClay.card(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        boxShadow: AppClay.nested(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(gradient: AppClay.iconChipGradient(tint), shape: BoxShape.circle),
                  child: Icon(icon, size: AppSizes.iconSm, color: tint),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.onSurface.withValues(alpha: 0.6),
                            ),
                      ),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.expand_more_rounded, color: colors.onSurface.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
