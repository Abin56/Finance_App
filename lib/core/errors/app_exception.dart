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
