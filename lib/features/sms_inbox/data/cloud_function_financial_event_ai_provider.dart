import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../domain/financial_event/financial_event_ai_provider.dart';

/// Calls the `classifyFinancialSms` Cloud Function (see
/// `functions/src/classifyFinancialSms.ts`) — the only concrete
/// [FinancialEventAiProvider] that reaches an actual LLM. The API key never
/// enters this app: it lives server-side in Firebase Secret Manager, and
/// this class only ever talks to Firebase's own authenticated callable-
/// function transport.
///
/// An 8s timeout plus a catch-all below guarantees [classify] returns within
/// a bounded time, every time — never throws, per
/// [FinancialEventAiProvider]'s contract.
class CloudFunctionFinancialEventAiProvider
    implements FinancialEventAiProvider {
  const CloudFunctionFinancialEventAiProvider(this._functions);

  final FirebaseFunctions _functions;

  static const _timeout = Duration(seconds: 8);

  @override
  Future<FinancialEventAiResult?> classify(
    FinancialEventAiRequest request,
  ) async {
    try {
      final callable = _functions.httpsCallable(
        'classifyFinancialSms',
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final result = await callable.call<Map<String, dynamic>>(
        request.toJson(),
      );
      return FinancialEventAiResult.fromJson(result.data);
    } on FirebaseFunctionsException catch (e) {
      // Never logs redactedBody/regexEvidence — only the error shape, so a
      // failure never leaks SMS content into device/crash logs.
      debugPrint(
        'FinancialEvent AI classify failed (falling back to regex-only): ${e.code} ${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint(
        'FinancialEvent AI classify failed (falling back to regex-only): $e',
      );
      return null;
    }
  }
}
