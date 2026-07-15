import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../domain/sms_conversion_target.dart';

/// The "What does this transaction represent?" bottom sheet — the 11
/// beginner-friendly options from the feature spec. Purely a picker; the
/// actual reuse-the-existing-screen wiring lives in `SmsConversionRouter`.
class SmsConvertSheet {
  static Future<SmsConversionTarget?> show(BuildContext context) {
    return showModalBottomSheet<SmsConversionTarget>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.sm),
                child: Text('What does this transaction represent?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
                  children: [
                    for (final target in SmsConversionTarget.values)
                      ListTile(
                        leading: CircleAvatar(child: Icon(target.icon)),
                        title: Text(target.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(target.description),
                        onTap: () => Navigator.of(sheetContext).pop(target),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
