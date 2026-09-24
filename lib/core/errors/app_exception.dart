/// Base exception type for local-storage and validation failures.
/// Repositories throw this (instead of letting Hive errors leak upward)
/// so the UI layer can show consistent, friendly error messages.
class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AppException: $message';
}

class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.cause});
}

/// Thrown when a loan/EMI payment or prepayment cannot be safely reversed —
/// e.g. a later payment or re-amortization has already happened on the same
/// loan. Carries [message] as a user-facing explanation; never thrown for a
/// merely-inconvenient case, only when reversing would silently rewrite
/// later financial history.
class PaymentReversalBlockedException extends AppException {
  const PaymentReversalBlockedException(super.message, {super.cause});
}
