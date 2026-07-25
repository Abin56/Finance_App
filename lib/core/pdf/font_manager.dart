import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// The three Noto Sans weights every PDF document renders with — chosen for
/// ₹ (U+20B9) glyph coverage that the `pdf` package's default Helvetica-family
/// base14 fonts lack. Regular is body text, SemiBold is section headings,
/// Bold is titles/totals/balances/important amounts.
class PdfFonts {
  const PdfFonts({required this.regular, required this.semiBold, required this.bold});

  final pw.Font regular;
  final pw.Font semiBold;
  final pw.Font bold;
}

/// Loads [PdfFonts] once per app process and reuses them for every PDF
/// generated afterward — font bytes are immutable and parsing them is real
/// (if small) work, so caching here is a deliberate, narrow exception to
/// "no global mutable state": it holds pure, unchanging data with no
/// observable side effects, not app state.
abstract class FontManager {
  FontManager._();

  static PdfFonts? _cached;

  static Future<PdfFonts> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final regularData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final semiBoldData = await rootBundle.load('assets/fonts/NotoSans-SemiBold.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');

    final fonts = PdfFonts(
      regular: pw.Font.ttf(regularData),
      semiBold: pw.Font.ttf(semiBoldData),
      bold: pw.Font.ttf(boldData),
    );
    _cached = fonts;
    return fonts;
  }
}
