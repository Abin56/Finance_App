import 'package:finance_app/core/utils/reminder_offset_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reminderOffsetLabel', () {
    test('labels 0 as Today', () {
      expect(reminderOffsetLabel(0), 'Today');
    });

    test('labels 1 as Tomorrow', () {
      expect(reminderOffsetLabel(1), 'Tomorrow');
    });

    test('labels any other value as "N days before"', () {
      expect(reminderOffsetLabel(3), '3 days before');
      expect(reminderOffsetLabel(5), '5 days before');
      expect(reminderOffsetLabel(14), '14 days before');
    });
  });
}
