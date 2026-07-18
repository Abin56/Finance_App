import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../emi/domain/emi.dart';
import '../../../emi/domain/emi_payment_breakdown.dart';
import '../../../emi/domain/emi_status.dart';
import '../../../emi/presentation/providers/emi_providers.dart';

/// Folds every payment across every installment of [emi]'s schedule,
/// pairing each with its `EmiPaymentBreakdown` when one exists (null
/// otherwise) plus the installment's theoretical principal/interest split
/// (for providers that need to fall back to it) — the shared fan-out every
/// charge-total provider below needs, so each doesn't independently re-walk
/// installments/payments/breakdowns.
Iterable<
    ({
      double amountDue,
      double amountPaid,
      double? principalPortion,
      double? interestPortion,
      EmiPaymentBreakdown? breakdown,
    })> _paymentsWithBreakdown(Ref ref, Emi emi) sync* {
  final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
  final breakdowns = ref.watch(emiPaymentBreakdownsStreamProvider(emi.id)).value ?? const [];
  final breakdownByPaymentId = {for (final b in breakdowns) b.paymentId: b};

  for (final installment in installments) {
    final payments =
        ref.watch(installmentPaymentsStreamProvider((scheduleId: emi.scheduleId, installmentId: installment.id))).value ??
            const [];
    for (final payment in payments) {
      yield (
        amountDue: installment.amountDue,
        amountPaid: payment.amount,
        principalPortion: installment.principalPortion,
        interestPortion: installment.interestPortion,
        breakdown: breakdownByPaymentId[payment.id],
      );
    }
  }
}

/// Derived EMI report stats — no new persisted entity or repository, every
/// value is a pure aggregation over already-streamed `emisStreamProvider` +
/// per-schedule `installmentsStreamProvider` data.

/// Sum of amountPaid across every installment of every EMI's schedule.
final totalEmiPaidProvider = Provider<double>((ref) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis.fold(0.0, (sum, emi) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    return sum + installments.fold(0.0, (s, i) => s + i.amountPaid);
  });
});

/// Sum of remaining amounts across every non-closed EMI — reuses
/// `totalRemainingEmiBalanceProvider` directly rather than recomputing it.
final remainingEmiProvider = Provider<double>((ref) => ref.watch(totalRemainingEmiBalanceProvider));

/// Sum of interest paid so far. Prefers each payment's explicit
/// `EmiPaymentBreakdown.interestPaid` when recorded (the real split from
/// the user's bank statement); falls back to the installment's theoretical
/// interestPortion apportioned by that payment's share of amountDue for
/// payments with no breakdown, so historical data still contributes.
/// Installments with no interest split (flat, non-interest EMIs) and no
/// breakdown contribute 0.
final interestPaidProvider = Provider<double>((ref) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis.fold(0.0, (sum, emi) {
    return sum +
        _paymentsWithBreakdown(ref, emi).fold(0.0, (s, p) {
          if (p.breakdown != null) return s + p.breakdown!.interestPaid;
          final interestPortion = p.interestPortion;
          if (interestPortion == null || p.amountDue == 0) return s;
          return s + interestPortion * (p.amountPaid / p.amountDue);
        });
  });
});

/// Same logic as [interestPaidProvider], preferring
/// `EmiPaymentBreakdown.principalPaid` / falling back to principalPortion.
final principalPaidProvider = Provider<double>((ref) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis.fold(0.0, (sum, emi) {
    return sum +
        _paymentsWithBreakdown(ref, emi).fold(0.0, (s, p) {
          if (p.breakdown != null) return s + p.breakdown!.principalPaid;
          final principalPortion = p.principalPortion;
          if (principalPortion == null || p.amountDue == 0) return s;
          return s + principalPortion * (p.amountPaid / p.amountDue);
        });
  });
});

/// Count of installments with status == upcoming across active EMIs.
final upcomingEmiCountProvider = Provider<int>((ref) {
  final emis = ref.watch(activeEmisProvider);
  return emis.fold(0, (count, emi) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    return count + installments.where((i) => i.status == InstallmentStatus.upcoming).length;
  });
});

/// Count of distinct EMIs with an overdue installment — matches the
/// dashboard's `overdueEmisProvider.length` for consistency.
final overdueEmiReportCountProvider = Provider<int>((ref) => ref.watch(overdueEmisProvider).length);

/// Sum of remaining amounts across every overdue installment — reuses
/// `emiOverdueAmountProvider` directly rather than recomputing it.
final overdueEmiAmountProvider = Provider<double>((ref) => ref.watch(emiOverdueAmountProvider));

/// Count of every non-deleted EMI, regardless of status.
final totalEmisCountProvider = Provider<int>((ref) {
  return (ref.watch(emisStreamProvider).value ?? const []).length;
});

/// Count of EMIs whose derived status is closed.
final closedEmisCountProvider = Provider<int>((ref) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis.where((e) => ref.watch(emiStatusProvider(e)) == EmiStatus.closed).length;
});

/// Sums [selector] across every `EmiPaymentBreakdown` for every EMI —
/// payments with no breakdown simply contribute 0 for these charge types
/// (there's nothing to fall back to, unlike principal/interest).
double _sumBreakdownField(Ref ref, double Function(EmiPaymentBreakdown) selector) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis.fold(0.0, (sum, emi) {
    final breakdowns = ref.watch(emiPaymentBreakdownsStreamProvider(emi.id)).value ?? const [];
    return sum + breakdowns.fold(0.0, (s, b) => s + selector(b));
  });
}

final totalGstPaidProvider = Provider<double>((ref) => _sumBreakdownField(ref, (b) => b.gst));
final totalIgstPaidProvider = Provider<double>((ref) => _sumBreakdownField(ref, (b) => b.igst));
final totalInsuranceChargePaidProvider = Provider<double>((ref) => _sumBreakdownField(ref, (b) => b.insuranceCharge));
final totalProcessingFeePaidProvider = Provider<double>((ref) => _sumBreakdownField(ref, (b) => b.processingFee));
final totalPenaltyPaidProvider = Provider<double>((ref) => _sumBreakdownField(ref, (b) => b.penalty));
final totalOtherChargesPaidProvider = Provider<double>((ref) => _sumBreakdownField(ref, (b) => b.otherCharges));

/// Sum of every breakdown's `totalAmountPaid`, plus every payment with no
/// breakdown contributing its plain `InstallmentPayment.amount` — so this
/// total stays accurate whether or not every payment has a breakdown.
final overallAmountPaidProvider = Provider<double>((ref) {
  final emis = ref.watch(emisStreamProvider).value ?? const [];
  return emis.fold(0.0, (sum, emi) {
    return sum +
        _paymentsWithBreakdown(ref, emi).fold(0.0, (s, p) {
          return s + (p.breakdown?.totalAmountPaid ?? p.amountPaid);
        });
  });
});
