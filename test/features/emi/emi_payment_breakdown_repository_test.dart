import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/emi/data/emi_payment_breakdown_repository.dart';
import 'package:finance_app/features/emi/domain/emi_payment_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late EmiPaymentBreakdownRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('paymentBreakdowns').withConverter<EmiPaymentBreakdown>(
          fromFirestore: EmiPaymentBreakdown.fromFirestore,
          toFirestore: (b, _) => b.toFirestore(),
        );
    repository = EmiPaymentBreakdownRepository(collection);
  });

  group('EmiPaymentBreakdownRepository.createBreakdown', () {
    test('persists every field passed and defaults the rest', () async {
      final breakdown = await repository.createBreakdown(
        paymentId: 'payment-1',
        scheduleId: 'schedule-1',
        installmentId: 'installment-1',
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

      expect(breakdown.id, 'payment-1');
      expect(breakdown.principalPaid, 4200);
      expect(breakdown.interestPaid, 800);
      expect(breakdown.gst, 100);
      expect(breakdown.igst, 50);
      expect(breakdown.processingFee, 200);
      expect(breakdown.insuranceCharge, 150);
      expect(breakdown.serviceCharge, 30);
      expect(breakdown.penalty, 20);
      expect(breakdown.otherCharges, 10);
      expect(breakdown.notes, 'January EMI');

      final fetched = await repository.getByKey('payment-1');
      expect(fetched, isNotNull);
      expect(fetched!.principalPaid, 4200);
    });

    test('uses paymentId as the document id, enforcing 1:1', () async {
      await repository.createBreakdown(
        paymentId: 'payment-1',
        scheduleId: 'schedule-1',
        installmentId: 'installment-1',
        principalPaid: 1000,
      );
      // Recording a second breakdown for the same payment overwrites rather
      // than creating a duplicate document.
      await repository.createBreakdown(
        paymentId: 'payment-1',
        scheduleId: 'schedule-1',
        installmentId: 'installment-1',
        principalPaid: 2000,
      );

      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.single.principalPaid, 2000);
    });

    test('defaults every optional charge to 0 when not provided', () async {
      final breakdown = await repository.createBreakdown(
        paymentId: 'payment-2',
        scheduleId: 'schedule-1',
        installmentId: 'installment-2',
      );

      expect(breakdown.principalPaid, 0);
      expect(breakdown.interestPaid, 0);
      expect(breakdown.gst, 0);
      expect(breakdown.igst, 0);
      expect(breakdown.processingFee, 0);
      expect(breakdown.insuranceCharge, 0);
      expect(breakdown.serviceCharge, 0);
      expect(breakdown.penalty, 0);
      expect(breakdown.otherCharges, 0);
    });
  });
}
