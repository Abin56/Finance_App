import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/people/presentation/providers/people_providers.dart';
import '../payment_attribution_service.dart';

final paymentAttributionServiceProvider = Provider<PaymentAttributionService>((ref) {
  return PaymentAttributionService(
    ledgerRepositoryFor: (personId) => ref.watch(ledgerRepositoryProvider(personId)),
  );
});
