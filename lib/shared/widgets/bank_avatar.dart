import 'package:flutter/material.dart';

import '../../core/data/bank_registry.dart';

/// Colored-initials avatar for a bank, resolved from a persisted [bankId]
/// with an optional [fallbackName] match for accounts created before the
/// bank picker existed (see [BankRegistry.resolve]). Shows a neutral
/// generic bank icon when nothing resolves — never an empty placeholder.
class BankAvatar extends StatelessWidget {
  const BankAvatar({super.key, this.bankId, this.fallbackName, this.size = 40});

  final String? bankId;
  final String? fallbackName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bank = BankRegistry.resolve(bankId: bankId, fallbackName: fallbackName);
    if (bank == null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: BankRegistry.generic.primaryColor.withValues(alpha: 0.15),
        child: Icon(Icons.account_balance_rounded, size: size * 0.5, color: BankRegistry.generic.primaryColor),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bank.primaryColor,
      child: Text(
        bank.shortCode.length > 5 ? bank.shortCode.substring(0, 5) : bank.shortCode,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.24,
        ),
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
      ),
    );
  }
}
