import 'dashboard_widget_type.dart';

/// One renderable slot on a dashboard. Knows only its type, which
/// [WidgetConfiguration] (by [configId]) it points at, and whether it's
/// visible — no calculation or display logic lives here, so reordering,
/// hiding, or deleting a widget never touches the config it's built from.
class DashboardWidget {
  const DashboardWidget({
    required this.id,
    required this.type,
    required this.configId,
  });

  final String id;
  final DashboardWidgetType type;

  /// The [WidgetConfiguration.id] this slot renders. A [type] that
  /// [DashboardWidgetTypeX.supportsMultipleInstances] can have several
  /// [DashboardWidget]s of the same [type], each with its own [configId].
  final String configId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'configId': configId,
      };

  factory DashboardWidget.fromJson(Map<String, dynamic> json) {
    return DashboardWidget(
      id: json['id'] as String,
      type: DashboardWidgetType.values.byName(json['type'] as String),
      configId: json['configId'] as String,
    );
  }
}

/// A named, ordered list of [DashboardWidget]s — this is what a "dashboard
/// profile" (Personal / Business / Minimal) actually is. Switching the
/// active profile swaps which [DashboardLayout] is read; it never mutates
/// the underlying [WidgetConfiguration]s, so editing one profile can't
/// corrupt another, and two profiles can even share a widget instance by
/// referencing the same [DashboardWidget.configId] if that's ever wanted.
class DashboardLayout {
  const DashboardLayout({
    required this.id,
    required this.name,
    required this.widgets,
  });

  final String id;
  final String name;

  /// Order is the render order — index 0 is topmost.
  final List<DashboardWidget> widgets;

  DashboardLayout copyWith({String? name, List<DashboardWidget>? widgets}) {
    return DashboardLayout(
      id: id,
      name: name ?? this.name,
      widgets: widgets ?? this.widgets,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'widgets': widgets.map((w) => w.toJson()).toList(),
      };

  factory DashboardLayout.fromJson(Map<String, dynamic> json) {
    return DashboardLayout(
      id: json['id'] as String,
      name: json['name'] as String,
      widgets: (json['widgets'] as List<dynamic>)
          .map((w) => DashboardWidget.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }
}
