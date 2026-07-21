import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/card_network.dart';
import '../domain/credit_card_profile.dart';
import '../domain/credit_card_status.dart';
import 'shared_credit_limit_repository.dart';

/// Credit-card-profile persistence — no balance math here at all, since the
/// linked [Account] already tracks the card's running balance through
/// ordinary [Transaction]s (see [CreditCardProfile.accountId]).
class CreditCardRepository extends FirestoreCrudRepository<CreditCardProfile> {
  CreditCardRepository(super.collection, {this.sharedCreditLimitRepository});

  /// Used by [editCard] to trash a [SharedCreditLimit] once the card being
  /// removed from it was its last member — optional so tests/call sites
  /// that only ever create/edit standalone cards don't need to wire it up.
  final SharedCreditLimitRepository? sharedCreditLimitRepository;

  Future<CreditCardProfile> createCard({
    required String accountId,
    required int statementDay,
    required int paymentDueDay,
    required double creditLimit,
    double? minimumDuePercent,
    bool autoPay = false,
    CardNetwork? cardNetwork,
    String? lastFourDigits,
    double annualFee = 0,
    double joiningFee = 0,
    double? interestRatePercent,
    String? rewardNotes,
    String? autoDebitAccount,
    String? cardHolderName,
    String? sharedLimitId,
  }) async {
    _validate(
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      creditLimit: creditLimit,
      lastFourDigits: lastFourDigits,
      hasSharedLimit: sharedLimitId != null,
    );

    final card = CreditCardProfile(
      id: IdGenerator.generate(),
      accountId: accountId,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      creditLimit: creditLimit,
      minimumDuePercent: minimumDuePercent,
      autoPay: autoPay,
      createdAt: DateTime.now(),
      cardNetwork: cardNetwork,
      lastFourDigits: lastFourDigits,
      annualFee: annualFee,
      joiningFee: joiningFee,
      interestRatePercent: interestRatePercent,
      rewardNotes: rewardNotes,
      autoDebitAccount: autoDebitAccount,
      cardHolderName: cardHolderName,
      sharedLimitId: sharedLimitId,
    );
    await add(card.id, card);
    return card;
  }

  Future<void> editCard(
    CreditCardProfile card, {
    int? statementDay,
    int? paymentDueDay,
    double? creditLimit,
    double? minimumDuePercent,
    bool clearMinimumDuePercent = false,
    bool? autoPay,
    CreditCardStatus? status,
    CardNetwork? cardNetwork,
    String? lastFourDigits,
    double? annualFee,
    double? joiningFee,
    double? interestRatePercent,
    String? rewardNotes,
    String? autoDebitAccount,
    String? cardHolderName,
    bool clearCardHolderName = false,
    String? sharedLimitId,
    bool clearSharedLimitId = false,
  }) async {
    final previousSharedLimitId = card.sharedLimitId;
    final resolvedSharedLimitId = clearSharedLimitId ? null : (sharedLimitId ?? card.sharedLimitId);
    _validate(
      statementDay: statementDay ?? card.statementDay,
      paymentDueDay: paymentDueDay ?? card.paymentDueDay,
      creditLimit: creditLimit ?? card.creditLimit,
      lastFourDigits: lastFourDigits ?? card.lastFourDigits,
      hasSharedLimit: resolvedSharedLimitId != null,
    );

    card.updateField(
      field: 'statementDay',
      oldValue: card.statementDay,
      newValue: statementDay,
      apply: (v) => card.statementDay = v,
    );
    card.updateField(
      field: 'paymentDueDay',
      oldValue: card.paymentDueDay,
      newValue: paymentDueDay,
      apply: (v) => card.paymentDueDay = v,
    );
    card.updateField(
      field: 'creditLimit',
      oldValue: card.creditLimit,
      newValue: creditLimit,
      apply: (v) => card.creditLimit = v,
    );
    if (clearMinimumDuePercent) {
      card.recordEdit(
        field: 'minimumDuePercent',
        oldValue: card.minimumDuePercent?.toString() ?? 'none',
        newValue: 'none',
      );
      card.minimumDuePercent = null;
    } else {
      card.updateField(
        field: 'minimumDuePercent',
        oldValue: card.minimumDuePercent,
        newValue: minimumDuePercent,
        apply: (v) => card.minimumDuePercent = v,
      );
    }
    card.updateField(field: 'autoPay', oldValue: card.autoPay, newValue: autoPay, apply: (v) => card.autoPay = v);
    card.updateField(field: 'status', oldValue: card.status, newValue: status, apply: (v) => card.status = v);
    card.updateField(
      field: 'cardNetwork',
      oldValue: card.cardNetwork?.name,
      newValue: cardNetwork?.name,
      apply: (_) => card.cardNetwork = cardNetwork,
    );
    card.updateField(
      field: 'lastFourDigits',
      oldValue: card.lastFourDigits,
      newValue: lastFourDigits,
      apply: (v) => card.lastFourDigits = v,
    );
    card.updateField(
      field: 'annualFee',
      oldValue: card.annualFee,
      newValue: annualFee,
      apply: (v) => card.annualFee = v,
    );
    card.updateField(
      field: 'joiningFee',
      oldValue: card.joiningFee,
      newValue: joiningFee,
      apply: (v) => card.joiningFee = v,
    );
    card.updateField(
      field: 'interestRatePercent',
      oldValue: card.interestRatePercent,
      newValue: interestRatePercent,
      apply: (v) => card.interestRatePercent = v,
    );
    card.updateField(
      field: 'rewardNotes',
      oldValue: card.rewardNotes,
      newValue: rewardNotes,
      apply: (v) => card.rewardNotes = v,
    );
    card.updateField(
      field: 'autoDebitAccount',
      oldValue: card.autoDebitAccount,
      newValue: autoDebitAccount,
      apply: (v) => card.autoDebitAccount = v,
    );
    if (clearCardHolderName) {
      card.recordEdit(
        field: 'cardHolderName',
        oldValue: card.cardHolderName ?? 'none',
        newValue: 'none',
      );
      card.cardHolderName = null;
    } else {
      card.updateField(
        field: 'cardHolderName',
        oldValue: card.cardHolderName,
        newValue: cardHolderName,
        apply: (v) => card.cardHolderName = v,
      );
    }
    if (clearSharedLimitId) {
      card.recordEdit(
        field: 'sharedLimitId',
        oldValue: card.sharedLimitId ?? 'none',
        newValue: 'none',
      );
      card.sharedLimitId = null;
    } else {
      card.updateField(
        field: 'sharedLimitId',
        oldValue: card.sharedLimitId,
        newValue: sharedLimitId,
        apply: (v) => card.sharedLimitId = v,
      );
    }

    await update(card);

    // The shared limit this card just left (or moved out of) may now have
    // no active cards left pointing at it — trash it so it doesn't linger
    // as a dead "Existing shared credit limit" option. Runs for every
    // caller (UI, future API/import/sync paths), not just the one screen
    // that happens to remember to check.
    final sharedLimitLeft = previousSharedLimitId != null && previousSharedLimitId != resolvedSharedLimitId;
    final sharedLimits = sharedCreditLimitRepository;
    if (sharedLimitLeft && sharedLimits != null) {
      final remaining = await getAll();
      final hasOtherMembers = remaining.any((c) => c.id != card.id && c.sharedLimitId == previousSharedLimitId);
      if (!hasOtherMembers) {
        final sharedLimit = await sharedLimits.getByKey(previousSharedLimitId);
        if (sharedLimit != null && sharedLimit.deletedAt == null) {
          await sharedLimits.softDelete(sharedLimit);
        }
      }
    }
  }

  void _validate({
    required int statementDay,
    required int paymentDueDay,
    required double creditLimit,
    String? lastFourDigits,
    bool hasSharedLimit = false,
  }) {
    if (statementDay < 1 || statementDay > 31) {
      throw const AppException('Statement day must be between 1 and 31');
    }
    if (paymentDueDay < 1 || paymentDueDay > 31) {
      throw const AppException('Payment due day must be between 1 and 31');
    }
    if (!hasSharedLimit && creditLimit <= 0) {
      throw const AppException('Credit limit must be greater than 0');
    }
    if (lastFourDigits != null && !RegExp(r'^\d{4}$').hasMatch(lastFourDigits)) {
      throw const AppException('Last 4 digits must be exactly 4 numbers');
    }
  }
}
