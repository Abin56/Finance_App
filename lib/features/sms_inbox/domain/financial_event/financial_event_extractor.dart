import 'dart:math' as math;

import '../../../categories/domain/category.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../../core/utils/id_generator.dart';
import '../account_card_matcher.dart';
import '../account_match_result.dart';
import '../bank_sender_matcher.dart';
import '../merchant/merchant_category_suggester.dart';
import '../sms_confidence_scorer.dart';
import '../sms_inbox_item.dart';
import '../sms_transaction_category.dart';
import '../sms_transaction_direction.dart';
import 'ai_call_necessity.dart';
import 'ai_claim_validator.dart';
import 'ai_evidence_type.dart';
import 'automation_action.dart';
import 'category_resolver.dart';
import 'credit_card_semantics.dart';
import 'field_confidence.dart';
import 'financial_event.dart';
import 'financial_event_ai_provider.dart';
import 'financial_event_role.dart';
import 'financial_event_status.dart';
import 'financial_event_type.dart';
import 'financial_event_type_mapper.dart';
import 'merchant_identity.dart';
import 'merchant_identity_cache.dart';
import 'merchant_identity_resolver.dart';
import 'merchant_resolver.dart';
import 'merchant_source.dart';
import 'merchant_type.dart';
import 'payment_method.dart';
import 'payment_provider.dart';
import 'reminder_detector.dart';
import 'sms_body_redactor.dart';
import 'transaction_status.dart';
import 'transaction_status_signals.dart';

/// Builds one [FinancialEvent] for an already-parsed [SmsInboxItem],
/// reconciling the existing regex/parser evidence with an optional AI
/// opinion (see [FinancialEventAiProvider]) field by field.
///
/// Reconciliation rules (per field):
/// - Only one signal has a value → use it, at that signal's own confidence
///   (the AI's own confidence is discounted, since it's uncorroborated).
/// - Both agree → use the (regex) value at a boosted confidence.
/// - Both disagree on a **hard-fact** field (amount/direction/account) →
///   the regex value wins (an LLM can misparse digits; a wrong amount is the
///   worst class of error this system can make), confidence is capped low,
///   and the conflict is recorded in [FinancialEvent.reviewReasons] —
///   **never** silently resolved.
/// - Both disagree on [FinancialEvent.moneyMovement]/`transactionStatus` →
///   the more *conservative* value wins (money did NOT move / the more
///   restrictive status), never the more permissive one — the cost of
///   wrongly suppressing a real transaction (a human still sees it, just
///   without a "should I convert this" nudge) is far lower than the cost of
///   wrongly implying money moved when it didn't.
/// - Both disagree on a **soft-inference** field (merchant/category) → see
///   [MerchantResolver]/[CategoryResolver].
///
/// [accountMatch] is never touched by AI — the user's account list is never
/// sent off-device (see [FinancialEventAiRequest]); [AccountCardMatcher]
/// remains the sole source.
class FinancialEventExtractor {
  const FinancialEventExtractor({
    this.aiProvider,
    this.categoryResolver,
    this.reminderDetector = const ReminderDetector(),
    this.merchantIdentityResolver = const MerchantIdentityResolver(),
    this.merchantIdentityCache,
  });

  /// Null means "regex-only mode" — AI disabled/not configured. Never
  /// throws even when set; see [FinancialEventAiProvider.classify]. Even
  /// when set, [AiCallNecessity] decides per-message whether it's actually
  /// worth calling — see [extract]'s "AI should be selective" step.
  final FinancialEventAiProvider? aiProvider;

  /// Null means "no category suggestion" (extraction still produces a valid
  /// event; [FinancialEvent.category] is simply unresolved).
  final CategoryResolver? categoryResolver;

  final ReminderDetector reminderDetector;

  final MerchantIdentityResolver merchantIdentityResolver;

  /// Optional, per-scan cache — see `MerchantIdentityCache`'s doc comment.
  /// Null means "no caching" (every message resolved fresh); the pipeline
  /// passes one shared instance per scan (see `sms_inbox_providers.dart`).
  final MerchantIdentityCache? merchantIdentityCache;

  /// AI-only fields are discounted by this factor before being trusted —
  /// an AI-only value is uncorroborated by any independent signal.
  static const double _aiOnlyDiscount = 0.85;

  /// Added to `max(regexConfidence, aiConfidence)` when both signals agree —
  /// two independent methods reaching the same answer is itself evidence.
  static const double _agreementBonus = 0.15;

  /// The ceiling applied whenever two signals disagree on a field — a
  /// disagreement always means "a human should look at this", regardless of
  /// how confident either individual signal claimed to be.
  static const double _disagreementCap = 0.4;

  Future<FinancialEvent> extract({
    required SmsInboxItem item,
    required AccountMatchResult accountMatch,
    required List<Category> categories,
    AccountCardMatcher? accountCardMatcher,
  }) async {
    final parsed = item.parsed;
    if (parsed == null) {
      throw ArgumentError.value(
        item.id,
        'item',
        'FinancialEventExtractor requires an already-parsed SmsInboxItem.',
      );
    }
    final body = item.rawMessage.body;

    // --- Merchant identity (deterministic tiers only — no AI yet) ---------
    // Computed *before* deciding whether to call AI at all: a known-VPA or
    // known-catalog merchant is exactly the "no AI required" case (see
    // `AiCallNecessity`). Cached per scan so a run of SMS from the same
    // merchant doesn't repeat the same (cheap) catalog lookup, and — more
    // importantly — doesn't repeat an AI call for a merchant an earlier
    // message in this same scan already resolved.
    final regexMerchantText = parsed.merchantOrSender;
    final cachedIdentity = merchantIdentityCache?.get(
      merchantText: regexMerchantText,
    );
    var merchantIdentity =
        cachedIdentity ??
        merchantIdentityResolver.resolveDeterministic(
          regexMerchantText: regexMerchantText,
          body: body,
        );

    // --- AI selectivity ------------------------------------------------
    // "The objective is NOT to make AI classify every SMS" — only call out
    // when a deterministic signal is missing or genuinely ambiguous.
    final creditCardVerdict = CreditCardSemantics.detect(body);
    final compoundReversalDetected = _detectCompoundReversal(body);

    final preAiCategory = categoryResolver?.resolve(
      merchant: _merchantTextForCategoryLookup(
        merchantIdentity,
        regexMerchantText,
      ),
      transactionType: parsed.direction == SmsTransactionDirection.credit
          ? TransactionType.income
          : TransactionType.expense,
      categories: categories,
      smsCategory: parsed.category,
    );
    // A specific deterministic category (salary, interest, a bank fee,
    // cashback, an ATM withdrawal, a cash deposit, a loan EMI, a refund) is
    // self-explanatory on its own — it doesn't need `CategoryResolver` to
    // have found something too. The generic upi/bank/card fallback
    // categories carry no real signal, so those *do* still need a resolved
    // category (or AI) to count as "known".
    const specificCategories = {
      SmsTransactionCategory.salaryCredit,
      SmsTransactionCategory.interestCredit,
      SmsTransactionCategory.bankFee,
      SmsTransactionCategory.cashback,
      SmsTransactionCategory.atmWithdrawal,
      SmsTransactionCategory.cashDeposit,
      SmsTransactionCategory.loanEmiDebit,
      SmsTransactionCategory.refund,
    };
    final categoryIsKnownOrObvious =
        (preAiCategory != null &&
            preAiCategory.source != SuggestionSource.smsType) ||
        specificCategories.contains(parsed.category);

    // A merchant/counterparty was named in the SMS but couldn't be
    // identified — a message with *no* counterparty at all (a salary
    // credit, interest, a bank fee) never counts against this: there was
    // nothing to look up, so there's nothing "unresolved".
    final hasUnresolvedMerchantText =
        regexMerchantText != null &&
        regexMerchantText.trim().isNotEmpty &&
        !merchantIdentity.isKnown;

    // A merchant that was already resolved *by AI earlier in this same
    // scan* (a cache hit) means AI has already had its turn on this exact
    // counterparty — an unresolved category on a repeat message from it is
    // not new information AI hasn't already implicitly declined to give
    // (see the fake AI's `category: null` in the selectivity tests), so it
    // doesn't justify a second call on its own. This is the crux of what
    // `MerchantIdentityCache` exists for — see its doc comment.
    final categoryGapAlreadyAskedAbout =
        cachedIdentity != null && cachedIdentity.isKnown;

    final shouldCallAi =
        aiProvider != null &&
        AiCallNecessity.isNecessary(
          AiCallNecessityInput(
            hasUnresolvedMerchantText: hasUnresolvedMerchantText,
            hasUnresolvedCategory:
                !categoryIsKnownOrObvious && !categoryGapAlreadyAskedAbout,
            eventTypeIsAmbiguous:
                creditCardVerdict == CreditCardSemanticVerdict.ambiguous ||
                compoundReversalDetected,
          ),
        );

    final aiResult = shouldCallAi
        ? await aiProvider!.classify(_buildAiRequest(item))
        : null;

    final reviewReasons = <String>[];
    if (compoundReversalDetected) {
      reviewReasons.add(
        'This message describes both a debit and a same-day reversal — the net effect may be zero. Please confirm before recording this as spend.',
      );
    }

    final amount = _reconcileAmount(
      regexAmount: parsed.amount,
      parserConfidence: parsed.confidence,
      aiAmount: aiResult?.amount,
      aiConfidence: aiResult?.confidences.amount ?? 0.0,
      reasons: reviewReasons,
    );

    final directionResult = _reconcileDirection(
      regexDirection: parsed.direction,
      aiDirectionName: aiResult?.direction,
      reasons: reviewReasons,
    );

    var merchant = MerchantResolver.resolve(
      regexMerchant: parsed.merchantOrSender,
      aiMerchant: aiResult?.merchant,
      aiEvidence: aiResult?.evidenceMerchant,
      aiConfidence: aiResult?.confidences.merchant ?? 0.0,
      reasons: reviewReasons,
      body: body,
      aiEvidenceTypeName: aiResult?.evidenceMerchantType,
    );

    // Layer in the AI's identity opinion (only trusted when deterministic
    // tiers found nothing, and only with quoted evidence — see
    // `MerchantIdentityResolver.resolveWithAi`), then cache the final
    // result and — when it agrees with what `MerchantResolver` already
    // settled on — upgrade the plain merchant string to the catalog's
    // canonical spelling (`SWIGGY`/`swiggy@upi` → `Swiggy`; see
    // `MerchantCatalog`'s normalization doc).
    merchantIdentity = merchantIdentityResolver.resolveWithAi(
      deterministic: merchantIdentity,
      aiMerchant: aiResult?.merchant,
      aiEvidence: aiResult?.evidenceMerchant,
      aiConfidence: aiResult?.confidences.merchant ?? 0.0,
      aiMerchantTypeName: aiResult?.merchantType,
      aiPaymentProviderName: aiResult?.paymentProvider,
      body: body,
      reasons: reviewReasons,
      aiEvidenceTypeName: aiResult?.evidenceMerchantType,
    );
    merchantIdentityCache?.put(
      merchantIdentity,
      merchantText: regexMerchantText,
    );
    merchant = _applyCatalogNormalization(merchant, merchantIdentity);

    final moneyMovement = _reconcileMoneyMovement(
      body: body,
      aiMoneyMovement: aiResult?.moneyMovement,
      aiConfidence: aiResult?.confidences.moneyMovement ?? 0.0,
      reasons: reviewReasons,
    );

    final transactionStatus = _reconcileTransactionStatus(
      body: body,
      aiStatusName: aiResult?.transactionStatus,
      aiConfidence: aiResult?.confidences.transactionStatus ?? 0.0,
      reasons: reviewReasons,
    );

    final resolvedEventType = _resolveEventType(
      aiResult,
      parsed.category,
      moneyMovement,
      transactionStatus,
      creditCardVerdict,
    );

    final role = _resolveRole(aiResult, parsed.category, creditCardVerdict);

    final paymentMethod = _reconcilePaymentMethod(parsed.category, aiResult);

    final paymentProvider = merchantIdentity.paymentProvider == null
        ? const FieldConfidence<PaymentProvider>.unknown()
        : FieldConfidence<PaymentProvider>(
            value: merchantIdentity.paymentProvider,
            confidence: 0.8,
            source: aiResult?.paymentProvider != null
                ? EvidenceSource.aiOnly
                : EvidenceSource.regexOnly,
          );

    final merchantType =
        merchantIdentity.isKnown &&
            merchantIdentity.merchantType != MerchantType.unknown
        ? FieldConfidence<MerchantType>(
            value: merchantIdentity.merchantType,
            confidence: merchantIdentity.confidence,
            source: merchantIdentity.source == MerchantSource.aiInference
                ? EvidenceSource.aiOnly
                : EvidenceSource.regexOnly,
            regexEvidence: merchantIdentity.evidence,
          )
        : const FieldConfidence<MerchantType>.unknown();

    final isOwnAccountTransfer = _detectOwnAccountTransfer(
      body: body,
      accountCardMatcher: accountCardMatcher,
      sourceAccountId: accountMatch.matchedAccountId,
    );

    // A transfer between the user's own accounts is real money movement,
    // but it is neither an expense nor income from the user's overall
    // financial position — whichever coarser type the reconciliation above
    // landed on (payment/receipt/etc.), this always wins, since "which
    // account did this leave/enter" is a different question from "did the
    // user's net worth actually change." Never overrides a more specific,
    // already-correct verdict a reminder/reversal/refund would need (those
    // can't co-occur with a detected own-account transfer in practice —
    // the detector only fires on a real, completed money movement with a
    // second known last-4 elsewhere in the message).
    final eventType = isOwnAccountTransfer
        ? FinancialEventType.transfer
        : resolvedEventType;

    // The AI's category guess is only trusted when it quoted a substring
    // that genuinely occurs in the message AND that evidence's type
    // actually supports a category claim — same "never invent data"
    // principle as merchant identity, now type-aware (see
    // `AiClaimValidator`): a payment-rail/provider quote or a bare VPA can
    // never justify a category the way a merchant name or a descriptive
    // phrase can. A rejected claim is recorded, then dropped entirely
    // (treated as "AI had no category opinion"), never allowed to reach
    // CategoryResolver's AI-inference tier.
    final categoryVerdict = AiClaimValidator.validateCategory(
      claimedValue: aiResult?.category,
      evidence: aiResult?.evidenceCategory,
      evidenceType: aiResult?.evidenceCategoryType == null
          ? AiEvidenceType.exactText
          : AiEvidenceTypeX.fromName(aiResult?.evidenceCategoryType),
      body: body,
    );
    if (aiResult?.category != null && !categoryVerdict.accepted) {
      reviewReasons.add(
        'aiEvidenceNotGrounded: the AI suggested category "${aiResult!.category}" '
        'backed by "${aiResult.evidenceCategory}", but ${categoryVerdict.rejectionReason} — ignored.',
      );
    }
    final groundedAiCategoryName = categoryVerdict.accepted
        ? aiResult?.category
        : null;

    // A reminder/failed/pending message describes no real spending yet —
    // suggesting a category for it would misleadingly imply otherwise, so
    // category resolution is skipped entirely rather than just left
    // low-confidence. A transfer between the user's own accounts is the
    // same story from the opposite direction: real money movement, but
    // neither an expense nor income — it has no spending category at all
    // (see Part 7 of the Phase 5 SMS rebuild plan: "must not count this as
    // +₹10,000 income or -₹10,000 expense").
    final categorySuggestion =
        moneyMovement.value == false || isOwnAccountTransfer
        ? null
        : categoryResolver?.resolve(
            merchant: _merchantTextForCategoryLookup(
              merchantIdentity,
              merchant.value,
            ),
            transactionType:
                directionResult.direction == SmsTransactionDirection.credit
                ? TransactionType.income
                : TransactionType.expense,
            categories: categories,
            smsCategory: parsed.category,
            aiCategoryName: groundedAiCategoryName,
          );
    final category = categorySuggestion == null
        ? const FieldConfidence<String>.unknown()
        : FieldConfidence<String>(
            value: categorySuggestion.categoryId,
            confidence:
                categorySuggestion.source == SuggestionSource.aiInference
                ? 0.6
                : 0.9,
            source: categorySuggestion.source == SuggestionSource.aiInference
                ? EvidenceSource.aiOnly
                : EvidenceSource.regexOnly,
          );

    final subcategory = moneyMovement.value == false
        ? null
        : _subcategoryFor(aiResult, categories);

    if (!accountMatch.isResolved && moneyMovement.value != false) {
      // An unresolved account only matters once we know money actually
      // moved — flagging "which account?" for a reminder/failed message
      // that will never become a transaction just adds noise.
      reviewReasons.add(accountMatch.matchReason);
    }

    return FinancialEvent(
      id: IdGenerator.generate(),
      primarySmsItemId: item.id,
      eventType: eventType,
      role: role,
      status: FinancialEventStatus.pendingReview,
      direction: directionResult.direction,
      amount: amount,
      merchant: merchant,
      category: category,
      paymentMethod: paymentMethod,
      accountMatch: FieldConfidence<String>(
        value: accountMatch.matchedAccountId,
        confidence: accountMatch.isResolved
            ? (accountMatch.bankConfirmed ? 1.0 : 0.7)
            : 0.0,
        source: EvidenceSource.regexOnly,
        regexEvidence: accountMatch.matchReason,
      ),
      moneyMovement: moneyMovement,
      transactionStatus: transactionStatus,
      matchedCardId: accountMatch.matchedCardId,
      normalizedSender: BankSenderMatcher.normalize(item.rawMessage.address),
      eventDate: parsed.dateTime,
      // Overwritten by FinancialEventConfidenceEngine immediately after
      // construction (see the pipeline integration step) — a neutral
      // placeholder here keeps this class from depending on that engine.
      overallConfidence: 0.0,
      confidenceLevel: ConfidenceLevel.low,
      automationAction: AutomationAction.needsReview,
      needsReview:
          directionResult.hasConflict ||
          amount.source == EvidenceSource.bothDisagree ||
          moneyMovement.source == EvidenceSource.bothDisagree ||
          transactionStatus.source == EvidenceSource.bothDisagree ||
          reviewReasons.isNotEmpty,
      reviewReasons: reviewReasons,
      createdAt: DateTime.now(),
      referenceNumber: parsed.referenceNumber,
      subcategory: subcategory,
      isOwnAccountTransfer: isOwnAccountTransfer,
      paymentProvider: paymentProvider,
      merchantType: merchantType,
      aiRawResponse: null,
      aiModelVersion: null,
    );
  }

  FinancialEventAiRequest _buildAiRequest(SmsInboxItem item) {
    final parsed = item.parsed!;
    final body = item.rawMessage.body;
    return FinancialEventAiRequest(
      redactedBody: SmsBodyRedactor.redact(body),
      senderBankName: parsed.bankName,
      regexAmount: parsed.amount,
      regexDirection: parsed.direction.name,
      regexMaskedAccount: parsed.maskedAccountOrCard,
      regexReferenceNumber: parsed.referenceNumber,
      regexMerchantGuess: parsed.merchantOrSender,
      regexCategoryGuess: parsed.category.name,
      regexLooksLikeReminder: reminderDetector.detect(body).isReminder,
      regexTransactionStatus: TransactionStatusSignals.detect(body).name,
      clientRequestId: IdGenerator.generate(),
    );
  }

  FieldConfidence<double> _reconcileAmount({
    required double regexAmount,
    required double parserConfidence,
    required double? aiAmount,
    required double aiConfidence,
    required List<String> reasons,
  }) {
    if (aiAmount == null) {
      return FieldConfidence<double>(
        value: regexAmount,
        confidence: parserConfidence,
        source: EvidenceSource.regexOnly,
        regexEvidence: regexAmount.toStringAsFixed(2),
      );
    }

    final agree = (regexAmount - aiAmount).abs() < 0.01;
    if (agree) {
      final boosted =
          (math.max(parserConfidence, aiConfidence) + _agreementBonus).clamp(
            0.0,
            1.0,
          );
      return FieldConfidence<double>(
        value: regexAmount,
        confidence: boosted,
        source: EvidenceSource.bothAgree,
        regexEvidence: regexAmount.toStringAsFixed(2),
        aiEvidence: aiAmount.toStringAsFixed(2),
      );
    }

    reasons.add(
      'Regex read ₹${regexAmount.toStringAsFixed(2)} but AI read ₹${aiAmount.toStringAsFixed(2)} — please confirm the amount.',
    );
    return FieldConfidence<double>(
      value: regexAmount,
      confidence: math.min(parserConfidence, _disagreementCap),
      source: EvidenceSource.bothDisagree,
      regexEvidence: regexAmount.toStringAsFixed(2),
      aiEvidence: aiAmount.toStringAsFixed(2),
    );
  }

  ({SmsTransactionDirection direction, bool hasConflict}) _reconcileDirection({
    required SmsTransactionDirection regexDirection,
    required String? aiDirectionName,
    required List<String> reasons,
  }) {
    final aiDirection = SmsTransactionDirectionX.fromName(aiDirectionName);
    if (aiDirection == null || aiDirection == regexDirection) {
      return (direction: regexDirection, hasConflict: false);
    }
    reasons.add(
      'Regex read this as a ${regexDirection.label.toLowerCase()} but AI read it as a ${aiDirection.label.toLowerCase()} — please confirm.',
    );
    // Hard-fact field: regex wins even on disagreement.
    return (direction: regexDirection, hasConflict: true);
  }

  /// Deterministic signal: a completed-transaction verb was present (a
  /// precondition for [item.parsed] existing at all) AND
  /// [ReminderDetector]/[TransactionStatusSignals] found no override —
  /// `true`. A [ReminderVerdict.isReminder] or a `failed`/`pending` status
  /// makes it `false`. `reversed`/`refunded` are real (inverse) movements in
  /// their own right, so they stay `true`.
  FieldConfidence<bool> _reconcileMoneyMovement({
    required String body,
    required bool? aiMoneyMovement,
    required double aiConfidence,
    required List<String> reasons,
  }) {
    final reminderVerdict = reminderDetector.detect(body);
    final status = TransactionStatusSignals.detect(body);
    final blockingStatus =
        status == TransactionStatus.failed ||
        status == TransactionStatus.pending;

    final regexValue = !(reminderVerdict.isReminder || blockingStatus);
    final regexConfidence = reminderVerdict.isReminder || blockingStatus
        ? 0.85
        : 0.7;
    final regexReason = reminderVerdict.isReminder
        ? reminderVerdict.reason
        : (blockingStatus
              ? 'This message describes a ${status.label.toLowerCase()} transaction, not completed money movement.'
              : null);

    if (aiMoneyMovement == null) {
      return FieldConfidence<bool>(
        value: regexValue,
        confidence: regexConfidence,
        source: EvidenceSource.regexOnly,
        regexEvidence: regexReason,
      );
    }

    if (aiMoneyMovement == regexValue) {
      return FieldConfidence<bool>(
        value: regexValue,
        confidence: (math.max(regexConfidence, aiConfidence) + _agreementBonus)
            .clamp(0.0, 1.0),
        source: EvidenceSource.bothAgree,
        regexEvidence: regexReason,
      );
    }

    // Disagreement: the more conservative (false) value always wins — see
    // this method's class-level doc comment.
    reasons.add(
      aiMoneyMovement
          ? 'The wording looks like a reminder or an incomplete transaction, but the AI read it as money that already moved — please confirm.'
          : 'The AI flagged this as not a completed transaction (e.g. a reminder or a failed/pending attempt) — please confirm before treating it as spending.',
    );
    return FieldConfidence<bool>(
      value: false,
      confidence: _disagreementCap,
      source: EvidenceSource.bothDisagree,
      regexEvidence: regexReason,
    );
  }

  FieldConfidence<TransactionStatus> _reconcileTransactionStatus({
    required String body,
    required String? aiStatusName,
    required double aiConfidence,
    required List<String> reasons,
  }) {
    final regexDetailed = TransactionStatusSignals.detectDetailed(body);
    final regexStatus = regexDetailed.status;
    // Explicit status wording ("successful", "has been debited") is trusted
    // more than a status merely *inferred* from a bare completion verb
    // ("Rs.500 debited...", no "successful"/"has been" framing) — the same
    // known-vs-inferred distinction the field-confidence model applies
    // everywhere else in this feature.
    final regexConfidence = regexDetailed.isInferred ? 0.55 : 0.75;
    final aiStatus = aiStatusName == null
        ? null
        : TransactionStatusX.fromName(aiStatusName);

    if (aiStatus == null || aiStatus == TransactionStatus.unknown) {
      return regexStatus == TransactionStatus.unknown
          ? const FieldConfidence<TransactionStatus>.unknown()
          : FieldConfidence<TransactionStatus>(
              value: regexStatus,
              confidence: regexConfidence,
              source: EvidenceSource.regexOnly,
            );
    }
    if (regexStatus == TransactionStatus.unknown) {
      return FieldConfidence<TransactionStatus>(
        value: aiStatus,
        confidence: (aiConfidence * _aiOnlyDiscount).clamp(0.0, 1.0),
        source: EvidenceSource.aiOnly,
      );
    }
    if (regexStatus == aiStatus) {
      return FieldConfidence<TransactionStatus>(
        value: regexStatus,
        confidence: (math.max(regexConfidence, aiConfidence) + _agreementBonus)
            .clamp(0.0, 1.0),
        source: EvidenceSource.bothAgree,
      );
    }

    // Hard-fact field: an explicit status keyword match (regex) is trusted
    // over the AI's semantic read on disagreement — status wording
    // ("failed", "successful", "pending") is rarely ambiguous.
    reasons.add(
      'Regex read the status as "${regexStatus.label}" but AI read "${aiStatus.label}" — please confirm what actually happened.',
    );
    return FieldConfidence<TransactionStatus>(
      value: regexStatus,
      confidence: _disagreementCap,
      source: EvidenceSource.bothDisagree,
    );
  }

  FinancialEventType _resolveEventType(
    FinancialEventAiResult? aiResult,
    SmsTransactionCategory smsCategory,
    FieldConfidence<bool> moneyMovement,
    FieldConfidence<TransactionStatus> transactionStatus,
    CreditCardSemanticVerdict creditCardVerdict,
  ) {
    if (moneyMovement.value == false) return FinancialEventType.reminder;
    if (aiResult?.eventType != null) {
      final aiType = _eventTypeFromAiName(aiResult!.eventType!);
      if (aiType != null && aiType != FinancialEventType.reminder)
        return aiType;
    }
    // Deterministic override: a credit-card purchase and a credit-card bill
    // payment both mention "credit card", but only `CreditCardSemantics`
    // distinguishes the verb shape — without this, both would fall through
    // to the coarse category mapper below, which has no bill-payment
    // concept of its own and would misclassify a bill payment as a
    // purchase (see the SMS AI rebuild plan's Phase 2 limitation).
    if (creditCardVerdict == CreditCardSemanticVerdict.purchase) {
      return FinancialEventType.creditCardPurchase;
    }
    if (creditCardVerdict == CreditCardSemanticVerdict.billPayment) {
      return FinancialEventType.creditCardBill;
    }
    // Deterministic override: `SmsTransactionCategory` has no "reversal"
    // concept of its own (only `TransactionStatusSignals` detects "reversed"
    // wording), so without AI a reversal would otherwise fall through to
    // the coarse bankCredit->receipt mapping. The status signal is cheap and
    // already computed, so use it here rather than leaving reversals
    // under-classified whenever AI is unavailable.
    if (transactionStatus.value == TransactionStatus.reversed)
      return FinancialEventType.reversal;
    return FinancialEventTypeMapper.eventTypeFor(smsCategory);
  }

  /// Mirrors [_resolveEventType]'s priority order (AI wins when present,
  /// then deterministic credit-card semantics, then the generic mapper) for
  /// the paired `role` field — a purchase is always an
  /// [FinancialEventRole.originalCharge]; a bill payment always resolves
  /// the charge it pays off, i.e. [FinancialEventRole.linkedSettlement].
  FinancialEventRole _resolveRole(
    FinancialEventAiResult? aiResult,
    SmsTransactionCategory smsCategory,
    CreditCardSemanticVerdict creditCardVerdict,
  ) {
    if (aiResult?.role != null) {
      final aiRole = _roleFromAiName(aiResult!.role!);
      if (aiRole != null) return aiRole;
    }
    if (creditCardVerdict == CreditCardSemanticVerdict.purchase)
      return FinancialEventRole.originalCharge;
    if (creditCardVerdict == CreditCardSemanticVerdict.billPayment)
      return FinancialEventRole.linkedSettlement;
    return FinancialEventTypeMapper.roleFor(smsCategory);
  }

  /// A single message narrating both a debit-shaped verb and a reversal in
  /// the same sentence ("₹5,000 was debited... and reversed shortly
  /// after") — the net effect may be zero, which neither `moneyMovement`
  /// nor `transactionStatus` alone can express (the reversal keyword wins
  /// `TransactionStatusSignals`' verdict, so the event still reads as a
  /// real, if inverse, movement — correct on its own, but the *compound*
  /// nature is exactly the ambiguity worth flagging for a human and
  /// surfacing to `AiCallNecessity`).
  bool _detectCompoundReversal(String body) {
    final hasDebitVerb = RegExp(
      r'\b(debited|paid|charged|spent|withdrawn)\b',
      caseSensitive: false,
    ).hasMatch(body);
    final hasReversal = RegExp(
      r'\b(reversed|reversal)\b',
      caseSensitive: false,
    ).hasMatch(body);
    return hasDebitVerb && hasReversal;
  }

  /// Upgrades [merchant]'s display value to [identity]'s catalog-canonical
  /// spelling (`SWIGGY`/`swiggy@upi` → `Swiggy`) — but only when they
  /// clearly refer to the same underlying entity (same normalized key) and
  /// [identity] came from a catalog tier, never an unrelated substitution.
  /// Never invents a name `MerchantResolver` didn't already independently
  /// arrive at some form of — this only *normalizes spelling*, it never
  /// introduces a merchant that wasn't already present in [merchant].
  FieldConfidence<String> _applyCatalogNormalization(
    FieldConfidence<String> merchant,
    MerchantIdentity identity,
  ) {
    if (!identity.isKnown || identity.displayName == null) return merchant;
    // Catalog tiers upgrade spelling directly; an AI-inferred identity only
    // qualifies when it's a *cached* result from earlier in this same scan
    // (identifiable by its evidence being the raw VPA/text this message
    // shares) — never a fresh AI-only guess from this message's own call,
    // which `MerchantResolver.resolve` above has already reconciled with
    // its own (independent) evidence rules.
    const eligibleSources = {
      MerchantSource.vpaCatalog,
      MerchantSource.merchantCatalog,
      MerchantSource.aiInference,
    };
    if (!eligibleSources.contains(identity.source)) return merchant;
    if (merchant.value == null) return merchant;
    if (merchant.value == identity.displayName) return merchant;
    // Only upgrade when `merchant.value` is *exactly* the same raw text the
    // catalog match was resolved from (the VPA string, or the trimmed SMS
    // text) — never a normalized-key comparison, which would wrongly equate
    // a VPA string (`swiggy@icici`, which normalizes to `"swiggy icici"`)
    // with the catalog's plain canonical-name key (`"swiggy"`). This also
    // means the upgrade only fires when regex — not an AI reconciliation
    // that already changed the value to something else — is still the
    // value's source, so it never silently substitutes an unrelated name.
    final sourceText = identity.vpa?.raw ?? identity.evidence;
    if (sourceText == null || merchant.value != sourceText) return merchant;
    return FieldConfidence<String>(
      value: identity.displayName,
      confidence: (merchant.confidence + 0.05).clamp(0.0, 1.0),
      source: merchant.source,
      aiEvidence: merchant.aiEvidence,
      regexEvidence: merchant.regexEvidence,
    );
  }

  /// Picks which text `CategoryResolver` should key off of — the plain,
  /// possibly-canonicalized [fallback] display value in general, but the
  /// merchant catalog's *original, un-collapsed* variant text
  /// ([MerchantIdentity.evidence]) specifically when [identity] came from
  /// the [MerchantSource.merchantCatalog] tier.
  ///
  /// This exists because catalog normalization is a *display* concern
  /// (`SWIGGY INSTAMART`/`swiggy instamart` should all read as one
  /// consistent brand name to a user) but category resolution needs the
  /// opposite: "Swiggy Instamart" is a grocery order, not a food order,
  /// and collapsing it to the bare canonical "Swiggy" before
  /// `MerchantCategorySuggester` ever sees it silently destroys exactly the
  /// distinction that would let it tell the two apart. Other tiers
  /// (vpaCatalog, explicitText, aiInference, unknown) are left alone: a VPA
  /// tier's `evidence` is the raw VPA string, useless for category lookup,
  /// and the others already carry their un-collapsed text in [fallback]
  /// (nothing normalizes their spelling), so substituting `evidence` there
  /// would be a no-op at best.
  String? _merchantTextForCategoryLookup(
    MerchantIdentity identity,
    String? fallback,
  ) {
    if (identity.source == MerchantSource.merchantCatalog &&
        identity.evidence != null) {
      return identity.evidence;
    }
    // Every other known tier (vpaCatalog, explicitText, aiInference) should
    // key off the resolved display name, exactly as before this method
    // existed — only the merchantCatalog tier's raw variant text is more
    // useful for category lookup than its canonicalized name (see this
    // method's class-level doc comment).
    return identity.isKnown ? identity.displayName : fallback;
  }

  /// Scans [body] for a second last-4-digit fragment (beyond whatever the
  /// SMS's own source account already resolved to) that also belongs to one
  /// of the user's other accounts/cards — strong evidence of a transfer
  /// between the user's own accounts rather than to an external payee. Pure
  /// regex/local-account-list work; the AI never sees the account list.
  bool _detectOwnAccountTransfer({
    required String body,
    required AccountCardMatcher? accountCardMatcher,
    required String? sourceAccountId,
  }) {
    if (accountCardMatcher == null) return false;
    final matches = RegExp(r'\b\d{4}\b').allMatches(body);
    for (final match in matches) {
      final lastFour = match.group(0)!;
      if (accountCardMatcher.isKnownLastFour(lastFour)) return true;
    }
    return false;
  }

  FieldConfidence<PaymentMethod> _reconcilePaymentMethod(
    SmsTransactionCategory smsCategory,
    FinancialEventAiResult? aiResult,
  ) {
    final fallback = FinancialEventTypeMapper.paymentMethodFor(smsCategory);
    final aiMethod = aiResult?.paymentMethod == null
        ? null
        : PaymentMethodX.fromName(aiResult!.paymentMethod);
    if (aiMethod == null || aiMethod == PaymentMethod.unknown) {
      return fallback == PaymentMethod.unknown
          ? const FieldConfidence<PaymentMethod>.unknown()
          : FieldConfidence<PaymentMethod>(
              value: fallback,
              confidence: 0.6,
              source: EvidenceSource.regexOnly,
            );
    }
    if (fallback == PaymentMethod.unknown || fallback == aiMethod) {
      return FieldConfidence<PaymentMethod>(
        value: aiMethod,
        confidence: fallback == aiMethod ? 0.9 : 0.7,
        source: fallback == aiMethod
            ? EvidenceSource.bothAgree
            : EvidenceSource.aiOnly,
      );
    }
    // Disagreement on payment method is low-stakes (doesn't move money
    // incorrectly) — take the AI's semantic read but don't flag review over
    // it alone.
    return FieldConfidence<PaymentMethod>(
      value: aiMethod,
      confidence: 0.5,
      source: EvidenceSource.bothDisagree,
    );
  }

  String? _subcategoryFor(
    FinancialEventAiResult? aiResult,
    List<Category> categories,
  ) {
    final aiCategoryName = aiResult?.category?.trim();
    if (aiCategoryName == null || aiCategoryName.isEmpty) return null;
    final matchesExisting = categories.any(
      (c) => c.name.toLowerCase() == aiCategoryName.toLowerCase(),
    );
    if (matchesExisting) return null;
    return aiCategoryName;
  }

  FinancialEventType? _eventTypeFromAiName(String name) {
    for (final type in FinancialEventType.values) {
      if (type.name.toLowerCase() == name.toLowerCase()) return type;
    }
    return null;
  }

  FinancialEventRole? _roleFromAiName(String name) {
    for (final role in FinancialEventRole.values) {
      if (role.name.toLowerCase() == name.toLowerCase()) return role;
    }
    return null;
  }
}
