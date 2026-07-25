import 'package:pdf/pdf.dart';

/// Design tokens for PDF documents, mirroring [AppColors]/[AppSizes] values —
/// duplicated deliberately, not re-exported, since `pdf` widgets use [PdfColor]
/// and plain `double`s, never Flutter's `Color`/`ThemeData`/`BuildContext`.
abstract class PdfTokens {
  PdfTokens._();

  // Brand — matches AppColors.primary exactly, not the generic finance-blue
  // placeholder, so an exported statement still looks like it came from FlowFi.
  static const PdfColor primary = PdfColor.fromInt(0xFF5B5FEF);
  static const PdfColor secondary = PdfColor.fromInt(0xFF00C2A8);

  // Status — matches AppColors success/warning/error/info/pending.
  static const PdfColor success = PdfColor.fromInt(0xFF1FB873);
  static const PdfColor warning = PdfColor.fromInt(0xFFFFA53E);
  static const PdfColor error = PdfColor.fromInt(0xFFFF5B5B);
  static const PdfColor info = PdfColor.fromInt(0xFF3E8EFF);
  static const PdfColor neutral = PdfColor.fromInt(0xFF6B6C7A);

  // Surfaces & text — matches AppColors light-mode values (PDF is always
  // rendered light, regardless of the device's theme, like the existing
  // expense receipt).
  static const PdfColor surface = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor surfaceVariant = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor outline = PdfColor.fromInt(0xFFE5E7EB);
  static const PdfColor textPrimary = PdfColor.fromInt(0xFF14141C);
  static const PdfColor textSecondary = PdfColor.fromInt(0xFF6B6C7A);

  // Spacing — same 4pt/8pt grid as AppSizes.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // Radii — matches AppSizes.radiusSm/radiusLg.
  static const double radiusSm = 6;
  static const double radiusLg = 10;
  static const double radiusPill = 999;

  // Typography scale (pt) — Title/Heading/Body/Caption hierarchy from the brief.
  static const double fontTitle = 22;
  static const double fontHeading = 14;
  static const double fontBody = 10;
  static const double fontCaption = 9;
}
