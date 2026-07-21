import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/financial_view_module.dart';
import '../../../../features/reports/domain/reports_period.dart';
import '../../domain/widget_configuration.dart';

/// Edit Mode's settings sheet for a `financialView` widget instance — picks
/// [WidgetConfiguration.financialViewModule] and [WidgetConfiguration.dateStrategy].
/// Returns the updated config via [Navigator.pop], leaving persistence to
/// the caller ([DashboardLayoutController.updateConfig]) so this sheet has
/// no side effects of its own.
class FinancialViewConfigSheet extends StatefulWidget {
  const FinancialViewConfigSheet({super.key, required this.config});

  final WidgetConfiguration config;

  static Future<WidgetConfiguration?> show(BuildContext context, WidgetConfiguration config) {
    return showModalBottomSheet<WidgetConfiguration>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FinancialViewConfigSheet(config: config),
    );
  }

  @override
  State<FinancialViewConfigSheet> createState() => _FinancialViewConfigSheetState();
}

class _FinancialViewConfigSheetState extends State<FinancialViewConfigSheet> {
  late FinancialViewModule _module = widget.config.financialViewModule;
  late DateRangeStrategy _strategy = widget.config.dateStrategy;
  late final _titleController = TextEditingController(text: widget.config.title);

  static const _strategyOptions = <DateRangeStrategy>[
    SalaryCycleToDate(),
    SalaryCycleFull(),
    ReportsPeriodStrategy(ReportsPeriod.thisMonth),
    ReportsPeriodStrategy(ReportsPeriod.lastMonth),
    LastNDays(30),
    ReportsPeriodStrategy(ReportsPeriod.thisYear),
    ReportsPeriodStrategy(ReportsPeriod.financialYear),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSizes.lg,
          right: AppSizes.lg,
          top: AppSizes.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSizes.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Configure Financial View', style: textTheme.titleMedium),
            const SizedBox(height: AppSizes.lg),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Widget name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSizes.lg),
            Text('Show', style: textTheme.labelLarge),
            const SizedBox(height: AppSizes.sm),
            Wrap(
              spacing: AppSizes.sm,
              runSpacing: AppSizes.sm,
              children: [
                for (final module in FinancialViewModule.values)
                  ChoiceChip(
                    label: Text(module.label),
                    selected: _module == module,
                    onSelected: (_) => setState(() => _module = module),
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.lg),
            Text('Date range', style: textTheme.labelLarge),
            const SizedBox(height: AppSizes.sm),
            Wrap(
              spacing: AppSizes.sm,
              runSpacing: AppSizes.sm,
              children: [
                for (final strategy in _strategyOptions)
                  ChoiceChip(
                    label: Text(strategy.label),
                    selected: _strategy.runtimeType == strategy.runtimeType &&
                        _strategy.label == strategy.label,
                    onSelected: (_) => setState(() => _strategy = strategy),
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    widget.config.copyWith(
                      title: _titleController.text.trim().isEmpty ? widget.config.title : _titleController.text.trim(),
                      financialViewModule: _module,
                      dateStrategy: _strategy,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
