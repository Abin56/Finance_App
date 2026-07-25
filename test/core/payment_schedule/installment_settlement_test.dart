import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_settlement.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:flutter_test/flutter_test.dart';

Installment _installment({
  required String id,
  required DateTime dueDate,
  double amountDue = 1000,
  double amountPaid = 0,
}) {
  return Installment(
    id: id,
    scheduleId: 'sched1',
    ownerType: OwnerType.emi,
    ownerId: 'emi1',
    sequenceNumber: 1,
    dueDate: dueDate,
    amountDue: amountDue,
    amountPaid: amountPaid,
    createdAt: dueDate,
  );
}

void main() {
  group('InstallmentSettlement.plan', () {
    test('fans a lump sum across installments oldest-first, exactly covering the total', () {
      final installments = [
        _installment(id: 'i1', dueDate: DateTime(2026, 1, 1), amountDue: 1000),
        _installment(id: 'i2', dueDate: DateTime(2026, 2, 1), amountDue: 500),
        _installment(id: 'i3', dueDate: DateTime(2026, 3, 1), amountDue: 300),
      ];

      final plan = InstallmentSettlement.plan(installments, 1800);

      expect(plan.portions.map((p) => p.installment.id), ['i1', 'i2', 'i3']);
      expect(plan.portions.map((p) => p.portion), [1000, 500, 300]);
      expect(plan.unallocated, 0);
      expect(plan.totalApplied, 1800);
    });

    test('a partial amount covers earlier installments fully and the last one partially', () {
      final installments = [
        _installment(id: 'i1', dueDate: DateTime(2026, 1, 1), amountDue: 1000),
        _installment(id: 'i2', dueDate: DateTime(2026, 2, 1), amountDue: 500),
        _installment(id: 'i3', dueDate: DateTime(2026, 3, 1), amountDue: 300),
      ];

      final plan = InstallmentSettlement.plan(installments, 1200);

      expect(plan.portions, hasLength(2));
      expect(plan.portions[0], (installment: installments[0], portion: 1000));
      expect(plan.portions[1], (installment: installments[1], portion: 200));
      expect(plan.unallocated, 0);
    });

    test('skips already-settled installments entirely', () {
      final settled = _installment(id: 'i1', dueDate: DateTime(2026, 1, 1), amountDue: 1000, amountPaid: 1000);
      final unpaid = _installment(id: 'i2', dueDate: DateTime(2026, 2, 1), amountDue: 500);

      final plan = InstallmentSettlement.plan([settled, unpaid], 500);

      expect(plan.portions, hasLength(1));
      expect(plan.portions.single.installment.id, 'i2');
    });

    test('reports unallocated when the amount exceeds total outstanding', () {
      final installments = [
        _installment(id: 'i1', dueDate: DateTime(2026, 1, 1), amountDue: 100),
        _installment(id: 'i2', dueDate: DateTime(2026, 2, 1), amountDue: 200),
      ];

      final plan = InstallmentSettlement.plan(installments, 1000);

      expect(plan.totalApplied, 300);
      expect(plan.unallocated, 700);
      expect(plan.portions.map((p) => p.portion), [100, 200]);
    });

    test('handles a single installment', () {
      final installment = _installment(id: 'i1', dueDate: DateTime(2026, 1, 1), amountDue: 400);

      final plan = InstallmentSettlement.plan([installment], 250);

      expect(plan.portions.single.portion, 250);
      expect(plan.unallocated, 0);
    });

    test('throws for a non-positive amount', () {
      final installment = _installment(id: 'i1', dueDate: DateTime(2026, 1, 1));

      expect(() => InstallmentSettlement.plan([installment], 0), throwsA(isA<AppException>()));
      expect(() => InstallmentSettlement.plan([installment], -10), throwsA(isA<AppException>()));
    });

    test('returns no portions and full unallocated when every installment is already settled', () {
      final settled = _installment(id: 'i1', dueDate: DateTime(2026, 1, 1), amountDue: 100, amountPaid: 100);

      final plan = InstallmentSettlement.plan([settled], 50);

      expect(plan.portions, isEmpty);
      expect(plan.unallocated, 50);
    });
  });
}
