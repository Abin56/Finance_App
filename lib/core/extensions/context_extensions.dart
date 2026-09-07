import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../theme/app_theme.dart';

/// Shorthand accessors for theme/media-query values used constantly
/// throughout the UI layer.
extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// FlowFi's custom Theme V2 tokens (hero-surface family, muted surface,
  /// tertiary text) that [ColorScheme] has no slot for — see
  /// `core/theme/app_theme.dart`'s [FlowFiColors].
  FlowFiColors get flowfi => Theme.of(this).extension<FlowFiColors>()!;

  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  bool get isTablet => screenWidth >= AppSizes.breakpointMobile;
  bool get isDesktop => screenWidth >= AppSizes.breakpointTablet;

  void pop<T extends Object?>([T? result]) => Navigator.of(this).pop(result);
}
