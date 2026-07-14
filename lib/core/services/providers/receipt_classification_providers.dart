import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/people/presentation/providers/people_providers.dart';
import '../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../receipt_classification_router.dart';

final receiptClassificationRouterProvider = Provider<ReceiptClassificationRouter>((ref) {
  return ReceiptClassificationRouter(
    transactionRepository: ref.watch(transactionRepositoryProvider),
    ledgerRepositoryFor: (personId) => ref.watch(ledgerRepositoryProvider(personId)),
  );
});
