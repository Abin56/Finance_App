import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';

/// Shorthand accessors for theme/media-query values used constantly
/// throughout the UI layer.
extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textTheme => Theme.of(this).textTheme;

  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  bool get isTablet => screenWidth >= AppSizes.breakpointMobile;
  bool get isDesktop => screenWidth >= AppSizes.breakpointTablet;

  void pop<T extends Object?>([T? result]) => Navigator.of(this).pop(result);
}
