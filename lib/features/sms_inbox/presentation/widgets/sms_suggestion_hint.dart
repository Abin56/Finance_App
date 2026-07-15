import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/merchant/merchant_category_suggester.dart';

/// A one-line note explaining where a pre-filled category came from.
///
/// Exists so a suggestion is never an unattributed guess: told *why* a
/// category was picked, the user can accept it at a glance or correct it with
/// confidence. Deliberately a passive hint, not a banner or a confirmation —
/// the value is already editable, so it must not interrupt.
class SmsSuggestionHint extends StatelessWidget {
  const SmsSuggestionHint({super.key, required this.source, this.merchant});

  final SuggestionSource source;

  /// The merchant the suggestion was drawn from. Naming it is what makes the
  /// history case meaningful ("You usually file Swiggy under this"); the hint
  /// falls back to generic copy when the merchant is unknown.
  final String? merchant;

  @override
  Widget build(BuildContext context) {
    final label = _label();

    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, size: AppSizes.iconSm, color: context.colors.primary),
          const SizedBox(width: AppSizes.xs),
          // Long merchant names must wrap rather than overflow at 360dp.
          Expanded(
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  String _label() {
    final name = merchant?.trim();
    final hasMerchant = name != null && name.isNotEmpty;

    switch (source) {
      case SuggestionSource.userHistory:
        return hasMerchant ? 'Suggested — you usually file $name here' : 'Suggested from your history';
      case SuggestionSource.knownMerchant:
        return hasMerchant ? 'Suggested for $name — you can change it' : 'Suggested — you can change it';
      case SuggestionSource.smsType:
        return 'Suggested from this SMS — you can change it';
    }
  }
}
