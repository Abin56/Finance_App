import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';

/// Static app info — name, tagline, and version. No dynamic package-info
/// lookup: the version string mirrors `pubspec.yaml`'s `version:` field,
/// same as every other static string in [AppStrings].
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _version = '1.0.0';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppStrings.appName, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSizes.sm),
              Text(AppStrings.tagline, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSizes.lg),
              Text('Version $_version', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
