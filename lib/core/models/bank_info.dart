import 'package:flutter/material.dart';

/// Static reference data describing one bank — resolved by id from
/// [BankRegistry] wherever a bank's name, initials, or brand color needs
/// to be shown. Never persisted itself; only [id] is stored on an
/// [Account]/[CreditCardProfile], so correcting a bank's color or name here
/// automatically applies everywhere without a data migration.
class BankInfo {
  const BankInfo({
    required this.id,
    required this.name,
    required this.shortCode,
    required this.primaryColor,
    this.isFrequent = false,
  });

  final String id;
  final String name;
  final String shortCode;
  final Color primaryColor;
  final bool isFrequent;
}
