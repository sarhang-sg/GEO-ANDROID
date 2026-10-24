/// A failed local operation, never a successful empty result.
final class CoreFailure implements Exception {
  const CoreFailure(this.code, this.message);
  final String code;
  final String message;
  Map<String, Object?> toJson() => {'code': code, 'message': message};
  @override
  String toString() => 'CoreFailure($code): $message';
}
