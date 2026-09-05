import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/filter/sms_date_range_filter.dart';
import '../../domain/filter/sms_filter_criteria.dart';
import '../../domain/sms_import_status.dart';
import '../../domain/sms_transaction_category.dart';
import '../providers/sms_inbox_providers.dart';

/// The SMS Inbox's filter sheet — grouped sections over a scrollable body
/// with a pinned action bar, matching the app's other filter sheets.
///
/// Edits a local draft and only writes [smsFilterCriteriaProvider] on Apply,
/// so a half-built filter never churns the feed underneath the sheet (and
/// Close genuinely discards). Sections render only when their data exists:
/// a bank the user has no SMS from, or a card with no last-4, is never
/// offered as a filter that could only match nothing.
class SmsFilterSheet extends ConsumerStatefulWidget {
  const SmsFilterSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const SmsFilterSheet._(),
    );
  }

  @override
  ConsumerState<SmsFilterSheet> createState() => _SmsFilterSheetState();
}

class _SmsFilterSheetState extends ConsumerState<SmsFilterSheet> {
  late SmsFilterCriteria _draft = ref.read(smsFilterCriteriaProvider);
  late final _minController = TextEditingController(
    text: _amountText(_draft.minAmount),
  );
  late final _maxController = TextEditingController(
    text: _amountText(_draft.maxAmount),
  );

  static String _amountText(double? amount) =>
      amount == null ? '' : amount.toStringAsFixed(0);

  /// True when both bounds are set and Min exceeds Max — a range that can
  /// never match anything, with no explanation otherwise.
  bool get _hasInvalidAmountRange =>
      _draft.minAmount != null &&
      _draft.maxAmount != null &&
      _draft.minAmount! > _draft.maxAmount!;

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _update(SmsFilterCriteria next) => setState(() => _draft = next);

  void _apply() {
    if (_hasInvalidAmountRange) return;
    ref.read(smsFilterCriteriaProvider.notifier).state = _draft;
    Navigator.of(context).pop();
  }

  void _clearAll() {
    _minController.clear();
    _maxController.clear();
    _update(_draft.cleared());
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _draft.customStart != null && _draft.customEnd != null
          ? DateTimeRange(start: _draft.customStart!, end: _draft.customEnd!)
          : null,
    );
    if (picked == null) return;
    _update(
      _draft.copyWith(
        datePreset: SmsDatePreset.custom,
        customStart: picked.start,
        customEnd: picked.end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(smsAvailableBanksProvider);
    final categories = ref.watch(smsAvailableCategoriesProvider);
    final cardOptions = ref.watch(smsCardFilterOptionsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            _Header(
              activeCount: _draft.activeCount,
              onClose: () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                children: [
                  if (categories.isNotEmpty)
                    _Section(
                      title: 'Transaction type',
                      icon: Icons.category_outlined,
                      hint: 'Select any that apply',
                      child: _ChipWrap(
                        children: [
                          for (final category in categories)
                            _Chip(
                              label: category.label,
                              selected: _draft.categories.contains(category),
                              onSelected: (selected) => _update(
                                _draft.copyWith(
                                  categories: selected
                                      ? {..._draft.categories, category}
                                      : _draft.categories.difference({
                                          category,
                                        }),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  _Section(
                    title: 'Money direction',
                    icon: Icons.swap_vert_rounded,
                    hint: 'Choose one',
                    child: _ChipWrap(
                      children: [
                        for (final direction in SmsMoneyDirection.values)
                          _SingleChoiceChip(
                            label: direction.label,
                            icon: _directionIcon(direction),
                            selected: _draft.direction == direction,
                            onSelected: () =>
                                _update(_draft.copyWith(direction: direction)),
                          ),
                      ],
                    ),
                  ),
                  _Section(
                    title: 'Date & time',
                    icon: Icons.calendar_month_outlined,
                    hint: 'Choose one',
                    child: _ChipWrap(
                      children: [
                        for (final preset in SmsDatePreset.values)
                          _SingleChoiceChip(
                            label:
                                preset == SmsDatePreset.custom &&
                                    _draft.customStart != null
                                ? _customLabel()
                                : preset.label,
                            selected: _draft.datePreset == preset,
                            onSelected: () {
                              if (preset == SmsDatePreset.custom) {
                                _pickCustomRange();
                                return;
                              }
                              _update(
                                _draft.copyWith(
                                  datePreset: preset,
                                  clearCustomRange: true,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  if (banks.isNotEmpty)
                    _Section(
                      title: 'Bank',
                      icon: Icons.account_balance_outlined,
                      hint: 'Select any that apply',
                      child: _ChipWrap(
                        children: [
                          for (final bank in banks)
                            _Chip(
                              label: bank,
                              selected: _draft.banks.contains(bank),
                              onSelected: (selected) => _update(
                                _draft.copyWith(
                                  banks: selected
                                      ? {..._draft.banks, bank}
                                      : _draft.banks.difference({bank}),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  _Section(
                    title: 'Conversion status',
                    icon: Icons.fact_check_outlined,
                    hint: 'Select any that apply',
                    child: _ChipWrap(
                      children: [
                        for (final status in SmsImportStatus.values)
                          _Chip(
                            label: status.label,
                            selected: _draft.statuses.contains(status),
                            onSelected: (selected) => _update(
                              _draft.copyWith(
                                statuses: selected
                                    ? {..._draft.statuses, status}
                                    : _draft.statuses.difference({status}),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Offered only when duplicates actually exist — a filter
                  // that could only ever come back empty is noise.
                  if (ref.watch(smsDuplicateCountProvider) > 0)
                    _Section(
                      title: 'Duplicates',
                      icon: Icons.content_copy_rounded,
                      child: _ChipWrap(
                        children: [
                          _Chip(
                            label:
                                'Review ${ref.watch(smsDuplicateCountProvider)} duplicates',
                            selected:
                                _draft.duplicates ==
                                SmsDuplicateVisibility.only,
                            onSelected: (selected) => _update(
                              _draft.copyWith(
                                duplicates: selected
                                    ? SmsDuplicateVisibility.only
                                    : SmsDuplicateVisibility.hidden,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _Section(
                    title: 'Amount',
                    icon: Icons.currency_rupee_rounded,
                    hint: 'Quick pick sets Min below, or enter your own range',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ChipWrap(
                          children: [
                            for (final threshold in const [
                              500.0,
                              1000.0,
                              5000.0,
                              10000.0,
                            ])
                              _SingleChoiceChip(
                                label:
                                    'Above ${CurrencyFormatter.instance.format(threshold)}',
                                selected: _draft.minAmount == threshold,
                                onSelected: () {
                                  final selected = _draft.minAmount != threshold;
                                  final next = selected ? threshold : null;
                                  _minController.text = _amountText(next);
                                  _update(
                                    selected
                                        ? _draft.copyWith(minAmount: threshold)
                                        : _draft.copyWith(clearMinAmount: true),
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSizes.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _AmountField(
                                controller: _minController,
                                label: 'Min',
                                hasError: _hasInvalidAmountRange,
                                onChanged: (value) => _update(
                                  value == null
                                      ? _draft.copyWith(clearMinAmount: true)
                                      : _draft.copyWith(minAmount: value),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSizes.sm),
                            Expanded(
                              child: _AmountField(
                                controller: _maxController,
                                label: 'Max',
                                hasError: _hasInvalidAmountRange,
                                onChanged: (value) => _update(
                                  value == null
                                      ? _draft.copyWith(clearMaxAmount: true)
                                      : _draft.copyWith(maxAmount: value),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_hasInvalidAmountRange) ...[
                          const SizedBox(height: AppSizes.xs),
                          Text(
                            'Min must not be greater than Max.',
                            style: context.textTheme.bodySmall?.copyWith(
                              color: context.colors.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (cardOptions.isNotEmpty)
                    _Section(
                      title: 'Credit card',
                      icon: Icons.credit_card_outlined,
                      hint: 'Select any that apply',
                      child: _ChipWrap(
                        children: [
                          for (final option in cardOptions)
                            _Chip(
                              label: option.label,
                              selected: _draft.cardIds.contains(option.id),
                              onSelected: (selected) => _update(
                                _draft.copyWith(
                                  cardIds: selected
                                      ? {..._draft.cardIds, option.id}
                                      : _draft.cardIds.difference({option.id}),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            _ActionBar(onClearAll: _clearAll, onApply: _apply),
          ],
        );
      },
    );
  }

  String _customLabel() {
    final start = _draft.customStart!;
    final end = _draft.customEnd!;
    return '${start.day}/${start.month} – ${end.day}/${end.month}';
  }

  IconData? _directionIcon(SmsMoneyDirection direction) {
    switch (direction) {
      case SmsMoneyDirection.any:
        return null;
      case SmsMoneyDirection.incoming:
        return Icons.south_west_rounded;
      case SmsMoneyDirection.outgoing:
        return Icons.north_east_rounded;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.activeCount, required this.onClose});

  final int activeCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.sm,
        AppSizes.sm,
        AppSizes.sm,
      ),
      child: Row(
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Filter SMS',
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (activeCount > 0)
                  Text(
                    '$activeCount active',
                    style: context.textTheme.bodySmall?.copyWith(color: AppClay.primaryAccent(context)),
                  )
                else
                  Text(
                    'Narrow down your inbox',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Pinned below the scrolling body. Lifts above the keyboard via viewInsets so
/// Apply stays reachable while an amount field is focused.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onClearAll, required this.onApply});

  final VoidCallback onClearAll;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.sm,
        AppSizes.lg,
        AppSizes.sm + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onClearAll,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppClay.primaryAccent(context),
                side: BorderSide(color: AppClay.primaryAccent(context).withValues(alpha: 0.4)),
              ),
              child: const Text('Clear All'),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                boxShadow: AppClay.glow(AppClay.primary),
              ),
              child: FilledButton(
                onPressed: onApply,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppClay.primaryGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    height: AppSizes.buttonHeight,
                    child: const Text('Apply Filters', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One filter group. [hint] states, in plain words, whether the chips below
/// behave as a checkbox group ("Select any that apply" — tapping one never
/// affects another) or a radio group ("Choose one" — tapping one switches
/// off whatever was picked before). Without this, both groups look and feel
/// identical (the same pill chip), which is exactly what made it unclear
/// which behavior to expect from any given section.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.icon, this.hint});

  final String title;
  final IconData? icon;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.sm,
        AppSizes.lg,
        AppSizes.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppClay.primary.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: AppClay.iconChipGradient(AppClay.primary),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 13, color: AppClay.primary),
                ),
                const SizedBox(width: AppSizes.xs),
              ],
              Text(
                title,
                style: context.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: AppSizes.xs),
                Expanded(
                  child: Text(
                    hint!,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.45),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          child,
        ],
      ),
    );
  }
}

/// Wrap rather than a horizontal strip: chips reflow onto more lines on a
/// narrow phone instead of overflowing or hiding options off-screen.
class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.xs,
      runSpacing: AppSizes.xs,
      children: children,
    );
  }
}

/// A multi-select chip — [FilterChip], which shows a checkmark on selection
/// per Material convention. Used for every facet backed by a `Set` (tapping
/// one never touches another): Transaction type, Bank, Conversion status,
/// Credit card, Duplicates.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      labelStyle: context.textTheme.labelSmall,
      selected: selected,
      onSelected: onSelected,
      showCheckmark: true,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
    );
  }
}

/// A single-select chip — [ChoiceChip], which fills solid on selection with
/// no checkmark, the Material convention for "picking this replaces
/// whatever else was picked" (radio-button behavior). Used for every facet
/// backed by a plain enum/value rather than a `Set`: Money direction, Date
/// & time, and the Amount section's quick-pick thresholds. Deliberately a
/// distinct widget from [_Chip] rather than a `showCheckmark: false` flag on
/// the same one — the visual difference is the whole point, so it shouldn't
/// be one easy-to-miss parameter away from looking identical again.
class _SingleChoiceChip extends StatelessWidget {
  const _SingleChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: icon == null ? null : Icon(icon, size: AppSizes.iconSm),
      labelStyle: context.textTheme.labelSmall,
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.hasError = false,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<double?> onChanged;

  /// True when this field is part of an invalid Min/Max range — highlights
  /// the border without duplicating the explanation text under both fields.
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      style: context.textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
        errorBorder: hasError
            ? OutlineInputBorder(
                borderSide: BorderSide(color: context.colors.error),
              )
            : null,
        enabledBorder: hasError
            ? OutlineInputBorder(
                borderSide: BorderSide(color: context.colors.error),
              )
            : null,
      ),
      // An unparseable or empty field clears the bound rather than pinning it
      // at 0, which would silently hide every row.
      onChanged: (value) => onChanged(double.tryParse(value.trim())),
    );
  }
}
