import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/data/bank_registry.dart';
import '../../../../core/models/bank_info.dart';
import '../../domain/card_network.dart';

/// A bank-card-styled visual — gradient face, bank name / nickname, masked
/// number, holder name, and a network wordmark — used as the live preview in
/// the add/edit form and as the card's identity in lists. The gradient is
/// derived from the card's single stored color so no new model fields are
/// needed; [compact] renders a slim chip-height variant for member rows.
class CreditCardVisual extends StatelessWidget {
  const CreditCardVisual({
    super.key,
    required this.title,
    required this.colorValue,
    this.bankId,
    this.cardNetwork,
    this.lastFourDigits,
    this.cardHolderName,
    this.compact = false,
  });

  final String title;
  final int colorValue;
  final String? bankId;
  final CardNetwork? cardNetwork;
  final String? lastFourDigits;
  final String? cardHolderName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = Color(colorValue);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [base, Color.lerp(base, Colors.black, 0.4)!],
    );
    // The face is always a saturated/dark gradient, so text stays white
    // with a soft secondary tone regardless of theme.
    const onCard = Colors.white;
    final onCardSoft = Colors.white.withValues(alpha: 0.75);
    final bankName = BankRegistry.byId(bankId)?.name;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: onCard, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (lastFourDigits != null && lastFourDigits!.isNotEmpty)
                    Text(
                      '••••  $lastFourDigits',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: onCardSoft,
                            letterSpacing: 2,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (cardNetwork != null) NetworkWordmark(network: cardNetwork!, height: 14),
          ],
        ),
      );
    }

    final bank = BankRegistry.byId(bankId);

    return AspectRatio(
      aspectRatio: 1.42,
      child: Container(
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bank != null) ...[
                  _BankBadge(bank: bank),
                  const SizedBox(width: AppSizes.sm),
                ],
                Expanded(
                  child: Text(
                    bankName ?? title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: onCard, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (cardNetwork != null) NetworkWordmark(network: cardNetwork!, height: 18),
              ],
            ),
            Text(
              lastFourDigits == null || lastFourDigits!.isEmpty
                  ? '••••   ••••   ••••   ••••'
                  : '••••   ••••   ••••   $lastFourDigits',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: onCard,
                    letterSpacing: 2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onCardSoft, letterSpacing: 0.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded-square badge standing in for a bank's logo mark — no logo
/// assets are shipped, so the bank's [BankInfo.shortCode] on its own brand
/// color is the closest visual match to the reference wallet-card look.
class _BankBadge extends StatelessWidget {
  const _BankBadge({required this.bank});

  final BankInfo bank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm * 0.6),
      ),
      child: Text(
        bank.shortCode[0],
        style: TextStyle(color: bank.primaryColor, fontWeight: FontWeight.w900, fontSize: 14),
      ),
    );
  }
}

/// A drawn-in-Flutter stand-in for each network's mark — styled wordmarks
/// (and Mastercard's twin circles), so no licensed logo assets are shipped.
class NetworkWordmark extends StatelessWidget {
  const NetworkWordmark({super.key, required this.network, this.height = 18});

  final CardNetwork network;
  final double height;

  @override
  Widget build(BuildContext context) {
    switch (network) {
      case CardNetwork.mastercard:
        return SizedBox(
          height: height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _circle(const Color(0xFFEB001B)),
              Transform.translate(
                offset: Offset(-height * 0.35, 0),
                child: _circle(const Color(0xFFF79E1B).withValues(alpha: 0.9)),
              ),
            ],
          ),
        );
      case CardNetwork.visa:
        return _word('VISA', italic: true);
      case CardNetwork.rupay:
        return _word('RuPay', italic: true);
      case CardNetwork.amex:
        return _word('AMEX');
    }
  }

  Widget _circle(Color color) =>
      Container(width: height, height: height, decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  Widget _word(String text, {bool italic = false}) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontSize: height * 0.8,
        fontWeight: FontWeight.w900,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        letterSpacing: 0.5,
      ),
    );
  }
}
