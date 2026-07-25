import 'package:finance_app/core/payment_schedule/domain/cycle_anchor.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_engine.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_source_type.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_cycle_item.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for `InstallmentCycleItem` — the EMI/Loan/splitExpense/Bill
/// adapter that existed with zero test coverage and zero consumers before
/// this file. Verifies the `OwnerType` -> `CycleSourceType` mapping and the
/// `isSettled`/`isOverdue` derivations, then runs it through
/// `CycleEngine.classifyForCarryForward` the same way `StatementCycleItem`/
/// `PersonTimelineCycleItem` are already exercised, so EMI/Loan wiring in
/// the provider layer sits on top of a tested adapter.
void main() {
  Installment installment({
    String id = 'i1',
    OwnerType ownerType = OwnerType.emi,
    required DateTime dueDate,
    double amountDue = 1000,
    double amountPaid = 0,
    bool isSkipped = false,
  }) {
    return Installment(
      id: id,
      scheduleId: 's1',
      ownerType: ownerType,
      ownerId: 'o1',
      sequenceNumber: 1,
      dueDate: dueDate,
      amountDue: amountDue,
      amountPaid: amountPaid,
      isSkipped: isSkipped,
      createdAt: dueDate,
    );
  }

  group('InstallmentCycleItem field mapping', () {
    test('sourceType maps every OwnerType to its matching CycleSourceType', () {
      expect(
        InstallmentCycleItem(installment(ownerType: OwnerType.loan, dueDate: DateTime(2026, 7, 1))).sourceType,
        CycleSourceType.loan,
      );
      expect(
        InstallmentCycleItem(installment(ownerType: OwnerType.emi, dueDate: DateTime(2026, 7, 1))).sourceType,
        CycleSourceType.emi,
      );
      expect(
        InstallmentCycleItem(installment(ownerType: OwnerType.splitExpense, dueDate: DateTime(2026, 7, 1)))
            .sourceType,
        CycleSourceType.splitExpense,
      );
      expect(
        InstallmentCycleItem(installment(ownerType: OwnerType.bill, dueDate: DateTime(2026, 7, 1))).sourceType,
        CycleSourceType.bill,
      );
    });

    test('cycleDate/totalAmount/paidAmount pass through from the wrapped Installment', () {
      final item = InstallmentCycleItem(
        installment(dueDate: DateTime(2026, 7, 15), amountDue: 500, amountPaid: 200),
      );

      expect(item.cycleDate, DateTime(2026, 7, 15));
      expect(item.totalAmount, 500);
      expect(item.paidAmount, 200);
      expect(item.remainingAmount, 300);
    });

    test('isSettled is true when fully paid', () {
      final item = InstallmentCycleItem(installment(dueDate: DateTime(2026, 7, 1), amountDue: 500, amountPaid: 500));
      expect(item.isSettled, isTrue);
    });

    test('isSettled is true when skipped, even if unpaid', () {
      final item = InstallmentCycleItem(installment(dueDate: DateTime(2026, 7, 1), isSkipped: true));
      expect(item.isSettled, isTrue);
    });

    test('isSettled is false when partially paid', () {
      final item = InstallmentCycleItem(installment(dueDate: DateTime(2026, 7, 1), amountDue: 500, amountPaid: 100));
      expect(item.isSettled, isFalse);
    });

    test('isOverdue reflects Installment.status == overdue', () {
      final overdue = InstallmentCycleItem(installment(dueDate: DateTime(2020, 1, 1)));
      final upcoming = InstallmentCycleItem(installment(dueDate: DateTime(2999, 1, 1)));

      expect(overdue.isOverdue, isTrue);
      expect(upcoming.isOverdue, isFalse);
    });

    test('carryForwardEligible defaults to true (not overridden)', () {
      final item = InstallmentCycleItem(installment(dueDate: DateTime(2026, 7, 1)));
      expect(item.carryForwardEligible, isTrue);
    });
  });

  group('InstallmentCycleItem + CycleEngine.classifyForCarryForward', () {
    const anchor = CycleAnchor(anchorDay: 17);
    final now = DateTime(2026, 7, 22); // current cycle: 18 Jul -> 17 Aug

    test('an unpaid previous-cycle installment carries forward', () {
      final item = InstallmentCycleItem(installment(dueDate: DateTime(2026, 7, 5)));

      final result = CycleEngine.classifyForCarryForward([item], anchor, now: now);

      expect(result.previousCyclePending.map((i) => i.installment.id), ['i1']);
    });

    test('a fully paid previous-cycle installment does not carry forward', () {
      final item = InstallmentCycleItem(
        installment(dueDate: DateTime(2026, 7, 5), amountDue: 500, amountPaid: 500),
      );

      final result = CycleEngine.classifyForCarryForward([item], anchor, now: now);

      expect(result.previousCyclePending, isEmpty);
    });

    test('a current-cycle installment always shows regardless of paid state', () {
      final item = InstallmentCycleItem(
        installment(dueDate: DateTime(2026, 7, 20), amountDue: 500, amountPaid: 500),
      );

      final result = CycleEngine.classifyForCarryForward([item], anchor, now: now);

      expect(result.current.map((i) => i.installment.id), ['i1']);
    });
  });
}
