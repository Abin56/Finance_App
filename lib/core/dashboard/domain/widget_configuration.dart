import '../../../features/reports/domain/reports_period.dart';
import 'dashboard_widget_type.dart';
import 'date_range_strategy.dart';
import 'financial_view_module.dart';

/// Persisted, per-instance settings for one dashboard widget. A
/// [DashboardWidgetType] that [DashboardWidgetTypeX.supportsMultipleInstances]
/// (currently only `financialView`) can have several [WidgetConfiguration]s
/// simultaneously — each with its own [dateStrategy], filters, and [title] —
/// so "Financial View · Salary Cycle" and "Financial View · Last 30 Days"
/// coexist as two independent widgets of the same type.
///
/// This is the only place a widget's settings live; [DashboardWidget] merely
/// points at one by [id], and every widget builder reads its own settings
/// from here rather than from ad hoc constructor parameters — so opening
/// Edit Mode and changing a setting never requires touching the widget's
/// render code.
class WidgetConfiguration {
  WidgetConfiguration({
    required this.id,
    required this.type,
    required this.title,
    this.dateStrategy = const ReportsPeriodStrategy(ReportsPeriod.thisMonth),
    this.financialViewModule = FinancialViewModule.combinedExpenses,
    this.size = DashboardWidgetSize.medium,
    this.isVisible = true,
    this.accountIds = const [],
    this.categoryIds = const [],
    this.personIds = const [],
  });

  final String id;
  final DashboardWidgetType type;
  String title;
  DateRangeStrategy dateStrategy;

  /// Only meaningful when [type] is [DashboardWidgetType.financialView].
  FinancialViewModule financialViewModule;

  DashboardWidgetSize size;
  bool isVisible;

  /// Empty means "all" for each filter — never used to mean "none".
  List<String> accountIds;
  List<String> categoryIds;
  List<String> personIds;

  WidgetConfiguration copyWith({
    String? title,
    DateRangeStrategy? dateStrategy,
    FinancialViewModule? financialViewModule,
    DashboardWidgetSize? size,
    bool? isVisible,
    List<String>? accountIds,
    List<String>? categoryIds,
    List<String>? personIds,
  }) {
    return WidgetConfiguration(
      id: id,
      type: type,
      title: title ?? this.title,
      dateStrategy: dateStrategy ?? this.dateStrategy,
      financialViewModule: financialViewModule ?? this.financialViewModule,
      size: size ?? this.size,
      isVisible: isVisible ?? this.isVisible,
      accountIds: accountIds ?? this.accountIds,
      categoryIds: categoryIds ?? this.categoryIds,
      personIds: personIds ?? this.personIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'dateStrategy': _dateStrategyToJson(dateStrategy),
        'financialViewModule': financialViewModule.name,
        'size': size.name,
        'isVisible': isVisible,
        'accountIds': accountIds,
        'categoryIds': categoryIds,
        'personIds': personIds,
      };

  factory WidgetConfiguration.fromJson(Map<String, dynamic> json) {
    return WidgetConfiguration(
      id: json['id'] as String,
      type: DashboardWidgetType.values.byName(json['type'] as String),
      title: json['title'] as String,
      dateStrategy: _dateStrategyFromJson(json['dateStrategy'] as Map<String, dynamic>),
      financialViewModule: FinancialViewModule.values.byName(json['financialViewModule'] as String),
      size: DashboardWidgetSize.values.byName(json['size'] as String),
      isVisible: json['isVisible'] as bool,
      accountIds: (json['accountIds'] as List<dynamic>).cast<String>(),
      categoryIds: (json['categoryIds'] as List<dynamic>).cast<String>(),
      personIds: (json['personIds'] as List<dynamic>).cast<String>(),
    );
  }
}

/// Tagged-union JSON encoding for [DateRangeStrategy] — each variant writes
/// its own `kind` plus whatever fields it needs, so adding a new strategy
/// only means adding a case here and to [_dateStrategyFromJson], never
/// touching [WidgetConfiguration] itself.
Map<String, dynamic> _dateStrategyToJson(DateRangeStrategy strategy) {
  return switch (strategy) {
    SalaryCycleToDate(:final anchorDay) => {'kind': 'salaryCycleToDate', 'anchorDay': anchorDay},
    SalaryCycleFull(:final anchorDay) => {'kind': 'salaryCycleFull', 'anchorDay': anchorDay},
    ReportsPeriodStrategy(:final period) => {'kind': 'reportsPeriod', 'period': period.name},
    LastNDays(:final days) => {'kind': 'lastNDays', 'days': days},
    CustomDateRange(:final start, :final end) => {
        'kind': 'customRange',
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      },
  };
}

DateRangeStrategy _dateStrategyFromJson(Map<String, dynamic> json) {
  switch (json['kind'] as String) {
    case 'salaryCycleToDate':
      return SalaryCycleToDate(anchorDay: json['anchorDay'] as int);
    case 'salaryCycleFull':
      return SalaryCycleFull(anchorDay: json['anchorDay'] as int);
    case 'reportsPeriod':
      return ReportsPeriodStrategy(
        ReportsPeriod.values.byName(json['period'] as String),
      );
    case 'lastNDays':
      return LastNDays(json['days'] as int);
    case 'customRange':
      return CustomDateRange(
        DateTime.parse(json['start'] as String),
        DateTime.parse(json['end'] as String),
      );
    default:
      throw ArgumentError('Unknown DateRangeStrategy kind: ${json['kind']}');
  }
}
