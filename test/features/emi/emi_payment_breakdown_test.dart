import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/emi/domain/emi_payment_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmiPaymentBreakdown.fromFirestore / toFirestore', () {
    test('round-trips every field', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('breakdowns').withConverter<EmiPaymentBreakdown>(
            fromFirestore: EmiPaymentBreakdown.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );

      final breakdown = EmiPaymentBreakdown(
        id: 'payment-1',
        paymentId: 'payment-1',
        scheduleId: 'schedule-1',
        installmentId: 'installment-1',
        createdAt: DateTime(2026, 1, 1),
        principalPaid: 4200,
        interestPaid: 800,
        gst: 100,
        igst: 50,
        processingFee: 200,
        insuranceCharge: 150,
        serviceCharge: 30,
        penalty: 20,
        otherCharges: 10,
        notes: 'January EMI',
      );
      await collection.doc(breakdown.id).set(breakdown);

      final fetched = (await collection.doc(breakdown.id).get()).data()!;
      expect(fetched.paymentId, 'payment-1');
      expect(fetched.scheduleId, 'schedule-1');
      expect(fetched.installmentId, 'installment-1');
      expect(fetched.principalPaid, 4200);
      expect(fetched.interestPaid, 800);
      expect(fetched.gst, 100);
      expect(fetched.igst, 50);
      expect(fetched.processingFee, 200);
      expect(fetched.insuranceCharge, 150);
      expect(fetched.serviceCharge, 30);
      expect(fetched.penalty, 20);
      expect(fetched.otherCharges, 10);
      expect(fetched.notes, 'January EMI');
    });

    test('defaults every optional field to 0/empty when absent', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('breakdowns').withConverter<EmiPaymentBreakdown>(
            fromFirestore: EmiPaymentBreakdown.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );

      final breakdown = EmiPaymentBreakdown(
        id: 'payment-2',
        paymentId: 'payment-2',
        scheduleId: 'schedule-1',
        installmentId: 'installment-2',
        createdAt: DateTime(2026, 1, 1),
      );
      await collection.doc(breakdown.id).set(breakdown);

      final fetched = (await collection.doc(breakdown.id).get()).data()!;
      expect(fetched.principalPaid, 0);
      expect(fetched.interestPaid, 0);
      expect(fetched.gst, 0);
      expect(fetched.igst, 0);
      expect(fetched.processingFee, 0);
      expect(fetched.insuranceCharge, 0);
      expect(fetched.serviceCharge, 0);
      expect(fetched.penalty, 0);
      expect(fetched.otherCharges, 0);
      expect(fetched.notes, '');
    });
  });

  group('EmiPaymentBreakdown computed getters', () {
    test('totalCharges sums every non-principal/interest field', () {
      final breakdown = EmiPaymentBreakdown(
        id: 'p1',
        paymentId: 'p1',
        scheduleId: 's1',
        installmentId: 'i1',
        createdAt: DateTime(2026, 1, 1),
        principalPaid: 4200,
        interestPaid: 800,
        gst: 100,
        igst: 50,
        processingFee: 200,
        insuranceCharge: 150,
        serviceCharge: 30,
        penalty: 20,
        otherCharges: 10,
      );

      expect(breakdown.totalCharges, 560); // 100+50+200+150+30+20+10
      expect(breakdown.totalAmountPaid, 5560); // 4200+800+560
    });

    test('totalCharges/totalAmountPaid are 0 when nothing is set', () {
      final breakdown = EmiPaymentBreakdown(
        id: 'p1',
        paymentId: 'p1',
        scheduleId: 's1',
        installmentId: 'i1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(breakdown.totalCharges, 0);
      expect(breakdown.totalAmountPaid, 0);
    });
  });
}
