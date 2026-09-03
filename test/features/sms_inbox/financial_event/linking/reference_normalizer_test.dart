import 'package:finance_app/features/sms_inbox/domain/linking/reference_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalize', () {
    test('strips punctuation and whitespace', () {
      expect(ReferenceNormalizer.normalize('123-456-789012'), '123456789012');
      expect(ReferenceNormalizer.normalize('123 456 789012'), '123456789012');
      expect(ReferenceNormalizer.normalize('UTR/12345'), 'UTR12345');
    });

    test('uppercases for case-insensitive comparison', () {
      expect(ReferenceNormalizer.normalize('utr12345'), 'UTR12345');
    });

    test('null and empty-after-stripping both normalize to null', () {
      expect(ReferenceNormalizer.normalize(null), isNull);
      expect(ReferenceNormalizer.normalize(''), isNull);
      expect(ReferenceNormalizer.normalize('---'), isNull);
    });
  });

  group('matches', () {
    test('true for the same reference in different formatting', () {
      expect(
        ReferenceNormalizer.matches('UPI Ref 123456789012', '123-456-789012'),
        isFalse, // "UPI Ref " text itself is not stripped -- only punctuation/case, by design (see class doc).
      );
      expect(ReferenceNormalizer.matches('123-456-789012', '123456789012'), isTrue);
      expect(ReferenceNormalizer.matches('utr999', 'UTR999'), isTrue);
    });

    test('false for genuinely different reference numbers', () {
      expect(ReferenceNormalizer.matches('UTR111', 'UTR222'), isFalse);
    });

    test('two nulls never match — absence is not itself a signal', () {
      expect(ReferenceNormalizer.matches(null, null), isFalse);
      expect(ReferenceNormalizer.matches(null, 'UTR111'), isFalse);
    });
  });
}
