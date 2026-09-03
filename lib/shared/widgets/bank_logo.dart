import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/data/bank_registry.dart';
import '../../core/models/bank_info.dart';

enum BankLogoShape { circle, roundedSquare }

/// Whether `assets/banks/logos/{bankId}.svg` (or `.png`) exists in the asset bundle. Memoizes the
/// **Future itself** (not just its resolved value) per path, so every `BankLogo` for the same bank
/// — a long account list, a picker sheet with 50+ rows — shares one in-flight/resolved probe.
///
/// This matters beyond just avoiding duplicate reads: `FutureBuilder` compares the `future` it was
/// given by *identity* across rebuilds, not by the value it eventually produces. Calling an async
/// function directly as the `future:` argument creates a new `Future` instance on every rebuild —
/// FutureBuilder then resets to "waiting" and re-renders each time, which under rapid rebuilds
/// (typing in a search box, a list scrolling) can defeat `pumpAndSettle` in tests entirely. Handing
/// back the same cached `Future` instance is what makes it settle once and stay settled.
class _LogoAssetCache {
  _LogoAssetCache._();
  static final Map<String, Future<bool>> _svg = {};
  static final Map<String, Future<bool>> _png = {};

  static Future<bool> _probe(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> svgExists(String bankId) => _svg.putIfAbsent(bankId, () => _probe('assets/banks/logos/$bankId.svg'));
  static Future<bool> pngExists(String bankId) => _png.putIfAbsent(bankId, () => _probe('assets/banks/logos/$bankId.png'));
}

/// Single source of truth for "show this bank's identity" everywhere in the app — Dashboard,
/// Accounts, Add/Edit Account, Bank Picker, Credit Cards, Transactions, Bills. Resolves a persisted
/// [bankId] (with an optional [fallbackName] match for pre-bank-picker accounts, same as the old
/// `BankAvatar` it replaces) and looks for a real logo asset before falling back to a brand-colored
/// initials badge.
///
/// Neither `assets/banks/logos/*.svg` nor `.png` ship with the repo yet — see
/// `docs/bank-logo-assets.md` for the exact file list expected — so today every bank renders its
/// initials badge. Drop a real logo file in with the matching bank id as its filename (e.g.
/// `assets/banks/logos/hdfc.svg`) and this widget picks it up automatically on next asset bundle
/// rebuild, no code change required.
class BankLogo extends StatelessWidget {
  const BankLogo({
    super.key,
    this.bankId,
    this.fallbackName,
    this.size = 40,
    this.shape = BankLogoShape.circle,
  });

  final String? bankId;
  final String? fallbackName;
  final double size;
  final BankLogoShape shape;

  BorderRadius get _radius => shape == BankLogoShape.circle
      ? BorderRadius.circular(size / 2)
      : BorderRadius.circular(size * 0.28);

  @override
  Widget build(BuildContext context) {
    final bank = BankRegistry.resolve(bankId: bankId, fallbackName: fallbackName);
    return Semantics(
      label: bank?.name ?? 'Bank not set',
      image: true,
      child: _build(bank),
    );
  }

  Widget _build(BankInfo? bank) {
    if (bank == null) return _GenericBadge(size: size, radius: _radius);
    if (bank.id == BankRegistry.generic.id) return _InitialsBadge(bank: bank, size: size, radius: _radius);

    return FutureBuilder<bool>(
      future: _LogoAssetCache.svgExists(bank.id),
      builder: (context, svgSnapshot) {
        if (svgSnapshot.data == true) {
          return _ImageBadge(size: size, radius: _radius, child: SvgPicture.asset('assets/banks/logos/${bank.id}.svg', fit: BoxFit.contain));
        }
        if (svgSnapshot.connectionState != ConnectionState.done) {
          // Still probing — show the initials badge rather than a blank frame; if a logo turns
          // out to exist this repaints once the probe resolves, which is imperceptible for a
          // cached in-bundle asset check.
          return _InitialsBadge(bank: bank, size: size, radius: _radius);
        }
        return FutureBuilder<bool>(
          future: _LogoAssetCache.pngExists(bank.id),
          builder: (context, pngSnapshot) {
            if (pngSnapshot.data == true) {
              return _ImageBadge(size: size, radius: _radius, child: Image.asset('assets/banks/logos/${bank.id}.png', fit: BoxFit.contain));
            }
            return _InitialsBadge(bank: bank, size: size, radius: _radius);
          },
        );
      },
    );
  }
}

class _ImageBadge extends StatelessWidget {
  const _ImageBadge({required this.size, required this.radius, required this.child});

  final double size;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}

class _InitialsBadge extends StatelessWidget {
  const _InitialsBadge({required this.bank, required this.size, required this.radius});

  final BankInfo bank;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bank.primaryColor, borderRadius: radius),
      child: Text(
        bank.shortCode.length > 5 ? bank.shortCode.substring(0, 5) : bank.shortCode,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.24),
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _GenericBadge extends StatelessWidget {
  const _GenericBadge({required this.size, required this.radius});

  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: BankRegistry.generic.primaryColor.withValues(alpha: 0.15), borderRadius: radius),
      child: Icon(Icons.account_balance_rounded, size: size * 0.5, color: BankRegistry.generic.primaryColor),
    );
  }
}
