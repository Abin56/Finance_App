import 'package:finance_app/core/services/security/pin_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinHasher.hash', () {
    test('is deterministic for the same pin+salt', () {
      final a = PinHasher.hash('1234', 'salt-a');
      final b = PinHasher.hash('1234', 'salt-a');
      expect(a, b);
    });

    test('differs when the salt differs, even for the same pin', () {
      final a = PinHasher.hash('1234', 'salt-a');
      final b = PinHasher.hash('1234', 'salt-b');
      expect(a, isNot(b));
    });

    test('differs when the pin differs, even for the same salt', () {
      final a = PinHasher.hash('1234', 'salt-a');
      final b = PinHasher.hash('5678', 'salt-a');
      expect(a, isNot(b));
    });

    test('never returns the raw pin or salt as a substring of the hash', () {
      final hash = PinHasher.hash('1234', 'salt-a');
      expect(hash.contains('1234'), isFalse);
      expect(hash.contains('salt-a'), isFalse);
    });
  });

  group('PinHasher.verify', () {
    test('returns true for the correct pin/salt/hash combination', () {
      const pin = '9999';
      const salt = 'a-real-salt';
      final hash = PinHasher.hash(pin, salt);
      expect(PinHasher.verify(pin, salt, hash), isTrue);
    });

    test('returns false for a wrong pin', () {
      const salt = 'a-real-salt';
      final hash = PinHasher.hash('9999', salt);
      expect(PinHasher.verify('0000', salt, hash), isFalse);
    });

    test('returns false for a wrong salt', () {
      final hash = PinHasher.hash('9999', 'salt-a');
      expect(PinHasher.verify('9999', 'salt-b', hash), isFalse);
    });

    test('returns false for a tampered hash', () {
      const pin = '9999';
      const salt = 'a-real-salt';
      final hash = PinHasher.hash(pin, salt);
      expect(PinHasher.verify(pin, salt, '$hash-tampered'), isFalse);
    });
  });
}
