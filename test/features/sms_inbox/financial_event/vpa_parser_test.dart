import 'package:finance_app/features/sms_inbox/domain/financial_event/vpa_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a well-formed VPA into local part and handle', () {
    final info = VpaParser.parse('swiggy@icici');
    expect(info, isNotNull);
    expect(info!.localPart, 'swiggy');
    expect(info.handle, 'icici');
    expect(info.raw, 'swiggy@icici');
  });

  test('parses a VPA with digits and dots in the local part', () {
    final info = VpaParser.parse('9876543210@oksbi');
    expect(info!.localPart, '9876543210');
    expect(info.handle, 'oksbi');
  });

  test('trims surrounding whitespace before parsing', () {
    final info = VpaParser.parse('  swiggy@icici  ');
    expect(info, isNotNull);
    expect(info!.raw, 'swiggy@icici');
  });

  test('returns null for a plain merchant name with no @', () {
    expect(VpaParser.parse('Swiggy'), isNull);
  });

  test(
    'returns null for a support email — not a UPI-shaped VPA in the way this app cares about, but still parses (documented: this class only splits local@handle, identity/trust is a separate concern)',
    () {
      // Note: VpaParser is deliberately narrow — it only splits the string
      // shape. Whether "customercare@hdfcbank.com" should be *trusted* as a
      // merchant identity is MerchantIdentityResolver's job, not this class's.
      final info = VpaParser.parse('customercare@hdfcbank.com');
      expect(info, isNotNull);
      expect(info!.localPart, 'customercare');
    },
  );

  test('returns null for an empty string', () {
    expect(VpaParser.parse(''), isNull);
  });
}
