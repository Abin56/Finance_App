import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/data/bank_registry.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../domain/card_network.dart';

/// Builds the diagonal gradient stops for a card face from its single
/// stored [base] color. A saturated color just blends toward black, but a
/// low-saturation pick (like the "Silver" swatch) does that same blend into
/// a flat, boring gray slab — so those get a cool bright highlight and a
/// deep charcoal-navy shadow instead, reading as brushed metal rather than
/// plain gray. Shared by every screen that paints a card face so a silver
/// card always looks the same wherever it's shown.
/// Corner radius for a bank-card face — deliberately rounder than the app's
/// otherwise-flat, sharp-cornered [AppSizes] radii (all 0 except the pill),
/// since a physical card reads wrong with square corners.
const double cardFaceRadius = 20;

List<Color> cardFaceGradientColors(Color base) {
  final hsl = HSLColor.fromColor(base);
  if (hsl.saturation < 0.18) {
    final highlight = HSLColor.fromAHSL(1, 208, 0.32, (hsl.lightness + 0.32).clamp(0.0, 0.88)).toColor();
    final shadow = HSLColor.fromAHSL(1, 230, 0.42, (hsl.lightness - 0.30).clamp(0.05, 1.0)).toColor();
    return [highlight, shadow];
  }
  return [base, Color.lerp(base, Colors.black, 0.4)!];
}

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
      colors: cardFaceGradientColors(base),
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
          borderRadius: BorderRadius.circular(cardFaceRadius * 0.6),
        ),
        child: Row(
          children: [
            if (bankId != null) ...[
              BankLogo(bankId: bankId, size: 22, shape: BankLogoShape.roundedSquare),
              const SizedBox(width: AppSizes.sm),
            ],
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
          borderRadius: BorderRadius.circular(cardFaceRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bank != null) ...[
                  BankLogo(bankId: bank.id, size: 28, shape: BankLogoShape.roundedSquare),
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
