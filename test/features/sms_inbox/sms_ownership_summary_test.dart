import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_ownership_summary.dart';
import 'package:flutter_test/flutter_test.dart';

SmsInboxItem _item(
  String id, {
  String? uid,
  SmsImportStatus status = SmsImportStatus.pending,
  String? duplicateOfId,
}) => SmsInboxItem(
  id: id,
  messageKey: 'k$id',
  rawMessage: RawSmsMessage(address: 'X', body: 'b', date: DateTime(2026)),
  dedupKey: 'd$id',
  status: status,
  createdAt: DateTime(2026),
  capturedForUid: uid,
  duplicateOfId: duplicateOfId,
);

void main() {
  test('splits pending rows into matching / missing / mismatching', () {
    final s = summarizeSmsOwnership([
      _item('1', uid: 'me'),
      _item('2'),
      _item('3'),
      _item('4', uid: 'other'),
      _item('5', uid: 'me', status: SmsImportStatus.ignored),
      _item('6', uid: 'me', duplicateOfId: '1'),
    ], 'me');
    expect(s.matching, 1);
    expect(s.missing, 2);
    expect(s.mismatching, 1);
    expect(s.total, 4);
  });

  test('signed out: nothing matches', () {
    final s = summarizeSmsOwnership([_item('1', uid: 'me'), _item('2')], null);
    expect(s.matching, 0);
    expect(s.missing, 1);
    expect(s.mismatching, 1);
  });
}
