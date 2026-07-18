import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/reports/presentation/providers/emi_report_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the rename from totalLoansCountProvider/
/// closedLoansCountProvider (which counted EMIs despite the "Loans" name,
/// a mislabeling bug in the EMI section of the Reports screen) to
/// totalEmisCountProvider/closedEmisCountProvider — confirms the counting
/// logic itself is unchanged by the rename.
void main() {
  late ProviderContainer container;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
  });

  test('totalEmisCountProvider counts every non-deleted EMI regardless of status', () async {
    final emis = container.read(emiRepositoryProvider);
    await emis.createEmi(
      name: 'Bike EMI',
      principalAmount: 1000,
      startDate: DateTime.now(),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 4,
    );
    await emis.createEmi(
      name: 'Home EMI',
      principalAmount: 5000,
      startDate: DateTime.now(),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 12,
    );

    await container.read(emisStreamProvider.future);

    expect(container.read(totalEmisCountProvider), 2);
  });

  test('closedEmisCountProvider counts only EMIs whose derived status is closed', () async {
    final emis = container.read(emiRepositoryProvider);
    final active = await emis.createEmi(
      name: 'Active EMI',
      principalAmount: 1000,
      startDate: DateTime.now(),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 4,
    );
    final toClose = await emis.createEmi(
      name: 'Closed EMI',
      principalAmount: 2000,
      startDate: DateTime.now(),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 4,
    );
    await emis.closeEmi(toClose);

    await container.read(emisStreamProvider.future);
    await container.read(installmentsStreamProvider(active.scheduleId).future);

    expect(container.read(totalEmisCountProvider), 2);
    expect(container.read(closedEmisCountProvider), 1);
  });
}
