import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../bills/presentation/providers/bill_occurrence_providers.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../data/account_deletion_service.dart';
import 'account_providers.dart';

/// Composes every repository the account permanent-delete cascade needs —
/// mirrors `expenseRepositoryProvider`'s composition shape, including
/// watching family providers lazily via a stored closure rather than at
/// build time. Lives in its own file (not appended to `account_providers.dart`)
/// specifically to avoid a circular *file* import: this needs
/// `expense_providers.dart`/`bill_providers.dart`/etc., which already import
/// `account_providers.dart` themselves.
final accountDeletionRepositoriesProvider = Provider<AccountDeletionRepositories>((ref) {
  final personRepository = ref.watch(personRepositoryProvider);
  return AccountDeletionRepositories(
    accountRepository: ref.watch(accountRepositoryProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
    billRepository: ref.watch(billRepositoryProvider),
    expenseRepository: ref.watch(expenseRepositoryProvider),
    personRepository: personRepository,
    ledgerRepositoryFor: (personId) => ref.watch(ledgerRepositoryProvider(personId)),
    paymentScheduleRepository: ref.watch(paymentScheduleRepositoryProvider),
    installmentRepositoryFor: (scheduleId) => ref.watch(installmentRepositoryProvider(scheduleId)),
    billOccurrenceRepositoryFor: (billId) => ref.watch(billOccurrenceRepositoryProvider(billId)),
    paymentRepositoryFor: (billId) => ref.watch(paymentRepositoryProvider(billId)),
  );
});
