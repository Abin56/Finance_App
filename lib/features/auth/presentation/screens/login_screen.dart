import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _handleSignIn() async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on SignInCancelledException {
      // User closed the account picker — not an error, nothing to show.
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _messageFor(e));
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'account-exists-with-different-credential':
        return 'This email is already linked to a different sign-in method.';
      default:
        return 'Sign-in failed (${e.code}). Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_balance_wallet_rounded, size: AppSizes.xxxl * 2, color: theme.colorScheme.primary),
                  const SizedBox(height: AppSizes.lg),
                  Text(AppStrings.appName, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    'Welcome — sign in to keep your finances safe and up to date.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSizes.xxl),
                  SizedBox(
                    width: double.infinity,
                    height: AppSizes.buttonHeight,
                    child: _isSigningIn
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            onPressed: _handleSignIn,
                            icon: const Icon(Icons.g_mobiledata_rounded, size: AppSizes.iconLg),
                            label: const Text('Continue with Google'),
                          ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSizes.md),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
