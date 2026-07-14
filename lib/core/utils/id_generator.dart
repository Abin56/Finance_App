import 'package:uuid/uuid.dart';

/// Single shared [Uuid] instance for generating local-only entity ids
/// (no backend, so v4 randomness without coordination is sufficient).
abstract class IdGenerator {
  IdGenerator._();

  static const _uuid = Uuid();

  static String generate() => _uuid.v4();
}
