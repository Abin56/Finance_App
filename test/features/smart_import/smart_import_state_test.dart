import 'package:finance_app/features/smart_import/domain/detected_transaction.dart';
import 'package:finance_app/features/smart_import/presentation/providers/smart_import_state.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

DetectedTransaction _row({
  String id = 'row',
  bool ready = true,
  bool isSelected = true,
  bool isDuplicate = false,
  bool duplicateAcknowledged = false,
}) {
  final row = DetectedTransaction(
    id: id,
    sourceImageIndex: 0,
    rawText: '',
    date: ready ? DateTime(2026, 9, 5) : null,
    rawDescription: ready ? 'Swiggy' : null,
    amount: ready ? 420 : null,
    type: TransactionType.expense,
  );
  row.isSelected = isSelected;
  row.isDuplicate = isDuplicate;
  row.duplicateAcknowledged = duplicateAcknowledged;
  return row;
}

void main() {
  group('SmartImportState.readyCount', () {
    test('counts a selected, complete, non-duplicate row', () {
      final state = SmartImportState(detected: [_row()]);
      expect(state.readyCount, 1);
    });

    test('excludes an unselected row', () {
      final state = SmartImportState(detected: [_row(isSelected: false)]);
      expect(state.readyCount, 0);
    });

    test('excludes a row that still needs review, even if selected', () {
      final state = SmartImportState(
        detected: [_row(ready: false, isSelected: true)],
      );
      expect(state.readyCount, 0);
    });

    test('excludes an unacknowledged duplicate', () {
      final state = SmartImportState(
        detected: [_row(isDuplicate: true, isSelected: false)],
      );
      expect(state.readyCount, 0);
    });

    test('includes an acknowledged duplicate', () {
      final state = SmartImportState(
        detected: [
          _row(
            isDuplicate: true,
            duplicateAcknowledged: true,
            isSelected: true,
          ),
        ],
      );
      expect(state.readyCount, 1);
    });
  });

  group('SmartImportState.errorSequence', () {
    test('bumps on every new error, even a repeated identical message', () {
      const initial = SmartImportState();
      final first = initial.copyWith(errorMessage: 'Something went wrong.');
      final second = first.copyWith(errorMessage: 'Something went wrong.');

      expect(first.errorSequence, initial.errorSequence + 1);
      expect(second.errorSequence, first.errorSequence + 1);
    });

    test('does not bump when no new error is set', () {
      final first = const SmartImportState().copyWith(errorMessage: 'Oops.');
      final unrelated = first.copyWith(accountId: 'acc-1');

      expect(unrelated.errorSequence, first.errorSequence);
    });
  });
}
