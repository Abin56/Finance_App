import 'package:flutter/material.dart';

import '../models/bank_info.dart';

/// Single source of truth for Indian bank reference data. Every module that
/// needs bank identity (Accounts, Credit Cards, SMS Inbox, Payments, History,
/// Reports, People, Loans, EMI, Bills, and any future Open Banking feature)
/// resolves it from here via [BankRegistry.byId] rather than keeping its own
/// copy — adding a bank later means appending one [BankInfo] to [all] and
/// nothing else.
abstract class BankRegistry {
  BankRegistry._();

  /// Shown when a bank couldn't be identified — never returned by [byId] for
  /// a real lookup, only used as a fallback display value by callers.
  static const generic = BankInfo(
    id: 'generic',
    name: 'Other / Generic Bank',
    shortCode: 'BANK',
    primaryColor: Color(0xFF6B6C7A),
  );

  static const List<BankInfo> all = [
    BankInfo(id: 'sbi', name: 'State Bank of India', shortCode: 'SBI', primaryColor: Color(0xFF2D6A4F), isFrequent: true),
    BankInfo(id: 'hdfc', name: 'HDFC Bank', shortCode: 'HDFC', primaryColor: Color(0xFFC0392B), isFrequent: true),
    BankInfo(id: 'icici', name: 'ICICI Bank', shortCode: 'ICICI', primaryColor: Color(0xFFE8720C), isFrequent: true),
    BankInfo(id: 'axis', name: 'Axis Bank', shortCode: 'AXIS', primaryColor: Color(0xFF7B1F3A), isFrequent: true),
    BankInfo(id: 'kotak', name: 'Kotak Mahindra Bank', shortCode: 'KOTAK', primaryColor: Color(0xFFC0272D), isFrequent: true),
    BankInfo(id: 'pnb', name: 'Punjab National Bank', shortCode: 'PNB', primaryColor: Color(0xFF8E1B2E), isFrequent: true),
    BankInfo(id: 'bob', name: 'Bank of Baroda', shortCode: 'BOB', primaryColor: Color(0xFFE8722C), isFrequent: true),
    BankInfo(id: 'canara', name: 'Canara Bank', shortCode: 'CNRB', primaryColor: Color(0xFFFFA53E), isFrequent: true),
    BankInfo(id: 'union_bank', name: 'Union Bank of India', shortCode: 'UBI', primaryColor: Color(0xFF1B5FA8)),
    BankInfo(id: 'indian_bank', name: 'Indian Bank', shortCode: 'IB', primaryColor: Color(0xFF1FB873)),
    BankInfo(id: 'iob', name: 'Indian Overseas Bank', shortCode: 'IOB', primaryColor: Color(0xFF2C5AA0)),
    BankInfo(id: 'federal', name: 'Federal Bank', shortCode: 'FED', primaryColor: Color(0xFF0F7B3E)),
    BankInfo(id: 'south_indian', name: 'South Indian Bank', shortCode: 'SIB', primaryColor: Color(0xFF14539A)),
    BankInfo(id: 'idfc_first', name: 'IDFC FIRST Bank', shortCode: 'IDFC', primaryColor: Color(0xFF7B2CBF)),
    BankInfo(id: 'indusind', name: 'IndusInd Bank', shortCode: 'IIB', primaryColor: Color(0xFF8B1E3F)),
    BankInfo(id: 'yes_bank', name: 'Yes Bank', shortCode: 'YES', primaryColor: Color(0xFF1F1F1F)),
    BankInfo(id: 'au_sfb', name: 'AU Small Finance Bank', shortCode: 'AU', primaryColor: Color(0xFFE8720C)),
    BankInfo(id: 'uco', name: 'UCO Bank', shortCode: 'UCO', primaryColor: Color(0xFF1B5FA8)),
    BankInfo(id: 'central_bank', name: 'Central Bank of India', shortCode: 'CBI', primaryColor: Color(0xFF1B4F72)),
    BankInfo(id: 'punjab_sind', name: 'Punjab & Sind Bank', shortCode: 'PSB', primaryColor: Color(0xFF7B241C)),
    BankInfo(id: 'karnataka', name: 'Karnataka Bank', shortCode: 'KBL', primaryColor: Color(0xFF117A65)),
    BankInfo(id: 'karur_vysya', name: 'Karur Vysya Bank', shortCode: 'KVB', primaryColor: Color(0xFF922B21)),
    BankInfo(id: 'dcb', name: 'DCB Bank', shortCode: 'DCB', primaryColor: Color(0xFFB9770E)),
    BankInfo(id: 'rbl', name: 'RBL Bank', shortCode: 'RBL', primaryColor: Color(0xFF616A6B)),
    BankInfo(id: 'bandhan', name: 'Bandhan Bank', shortCode: 'BDN', primaryColor: Color(0xFFAF601A)),
    BankInfo(id: 'city_union', name: 'City Union Bank', shortCode: 'CUB', primaryColor: Color(0xFF1F618D)),
    BankInfo(id: 'standard_chartered', name: 'Standard Chartered', shortCode: 'SC', primaryColor: Color(0xFF005EB8)),
    BankInfo(id: 'hsbc', name: 'HSBC India', shortCode: 'HSBC', primaryColor: Color(0xFFDB0011)),
    BankInfo(id: 'dbs', name: 'DBS Bank India', shortCode: 'DBS', primaryColor: Color(0xFFEC1C24)),
    BankInfo(id: 'citi', name: 'Citi (legacy)', shortCode: 'CITI', primaryColor: Color(0xFF003A79)),
    BankInfo(id: 'boi', name: 'Bank of India', shortCode: 'BOI', primaryColor: Color(0xFFB8860B)),
    BankInfo(id: 'bom', name: 'Bank of Maharashtra', shortCode: 'BOM', primaryColor: Color(0xFF1A5276)),
    BankInfo(id: 'j_and_k', name: 'Jammu & Kashmir Bank', shortCode: 'J&K', primaryColor: Color(0xFF7D3C98)),
    BankInfo(id: 'tmb', name: 'Tamilnad Mercantile Bank', shortCode: 'TMB', primaryColor: Color(0xFF196F3D)),
    BankInfo(id: 'nainital', name: 'Nainital Bank', shortCode: 'NTB', primaryColor: Color(0xFF1B4F72)),
    BankInfo(id: 'dhanlaxmi', name: 'Dhanlaxmi Bank', shortCode: 'DLB', primaryColor: Color(0xFF922B21)),
    BankInfo(id: 'csb', name: 'CSB Bank', shortCode: 'CSB', primaryColor: Color(0xFF117864)),
    BankInfo(id: 'equitas_sfb', name: 'Equitas Small Finance Bank', shortCode: 'EQSFB', primaryColor: Color(0xFFB03A2E)),
    BankInfo(id: 'ujjivan_sfb', name: 'Ujjivan Small Finance Bank', shortCode: 'UJSFB', primaryColor: Color(0xFFD35400)),
    BankInfo(id: 'jana_sfb', name: 'Jana Small Finance Bank', shortCode: 'JSFB', primaryColor: Color(0xFF1F618D)),
    BankInfo(id: 'suryoday_sfb', name: 'Suryoday Small Finance Bank', shortCode: 'SSFB', primaryColor: Color(0xFFCA6F1E)),
    BankInfo(id: 'esaf_sfb', name: 'ESAF Small Finance Bank', shortCode: 'ESFB', primaryColor: Color(0xFF1E8449)),
    BankInfo(id: 'north_east_sfb', name: 'North East Small Finance Bank', shortCode: 'NESFB', primaryColor: Color(0xFF117A65)),
    BankInfo(id: 'utkarsh_sfb', name: 'Utkarsh Small Finance Bank', shortCode: 'USFB', primaryColor: Color(0xFFB9770E)),
    BankInfo(id: 'paytm_pb', name: 'Paytm Payments Bank', shortCode: 'PPBL', primaryColor: Color(0xFF00259A)),
    BankInfo(id: 'airtel_pb', name: 'Airtel Payments Bank', shortCode: 'APB', primaryColor: Color(0xFFE40000)),
    BankInfo(id: 'india_post_pb', name: 'India Post Payments Bank', shortCode: 'IPPB', primaryColor: Color(0xFF8B1E3F)),
    BankInfo(id: 'fino_pb', name: 'Fino Payments Bank', shortCode: 'FPB', primaryColor: Color(0xFF7B241C)),
    BankInfo(id: 'nsdl_pb', name: 'NSDL Payments Bank', shortCode: 'NSDL', primaryColor: Color(0xFF1B4F72)),
    BankInfo(id: 'deutsche', name: 'Deutsche Bank', shortCode: 'DB', primaryColor: Color(0xFF0018A8)),
    BankInfo(id: 'barclays', name: 'Barclays India', shortCode: 'BARC', primaryColor: Color(0xFF00AEEF)),
    BankInfo(id: 'bofa', name: 'Bank of America India', shortCode: 'BOA', primaryColor: Color(0xFFE31837)),
    BankInfo(id: 'jpmorgan', name: 'JPMorgan Chase India', shortCode: 'JPM', primaryColor: Color(0xFF003087)),
    BankInfo(id: 'mizuho', name: 'Mizuho Bank India', shortCode: 'MIZ', primaryColor: Color(0xFF00529B)),
    BankInfo(id: 'sbm', name: 'SBM Bank India', shortCode: 'SBM', primaryColor: Color(0xFF1F618D)),
    BankInfo(id: 'idbi', name: 'IDBI Bank', shortCode: 'IDBI', primaryColor: Color(0xFF7B241C)),
  ];

  /// Fast lookup by id — the only field ever persisted on a domain entity.
  static BankInfo? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final bank in all) {
      if (bank.id == id) return bank;
    }
    return null;
  }

  /// Read-time, non-destructive fallback for accounts created before this
  /// feature existed — attempts to match old free-text bank names against
  /// the registry so their avatar/name resolve correctly without a data
  /// migration. Returns `null` (caller falls back to [generic]) if nothing
  /// matches.
  static BankInfo? matchByName(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final bank in all) {
      if (bank.name.toLowerCase() == normalized || bank.shortCode.toLowerCase() == normalized) {
        return bank;
      }
    }
    for (final bank in all) {
      if (normalized.contains(bank.name.toLowerCase()) || bank.name.toLowerCase().contains(normalized)) {
        return bank;
      }
    }
    return null;
  }

  /// The single resolution chain used at every display site: prefer the
  /// persisted [bankId]; if absent, fall back to matching [fallbackName]
  /// (e.g. an old free-text account name); otherwise `null` so the caller
  /// shows a generic placeholder.
  static BankInfo? resolve({String? bankId, String? fallbackName}) {
    final byIdMatch = byId(bankId);
    if (byIdMatch != null) return byIdMatch;
    if (fallbackName == null) return null;
    return matchByName(fallbackName);
  }

  static List<BankInfo> get frequent => all.where((b) => b.isFrequent).toList();

  /// Banks grouped under their first letter, alphabetically sorted within
  /// each group and across groups — feeds the picker's section list.
  static Map<String, List<BankInfo>> get groupedByLetter {
    final sorted = [...all]..sort((a, b) => a.name.compareTo(b.name));
    final groups = <String, List<BankInfo>>{};
    for (final bank in sorted) {
      final letter = bank.name[0].toUpperCase();
      groups.putIfAbsent(letter, () => []).add(bank);
    }
    return groups;
  }
}
