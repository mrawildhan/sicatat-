/// JSON received from SQLite or Supabase after its boundary has been checked.
typedef JsonMap = Map<String, Object?>;

JsonMap requireJsonMap(Object? value, {String source = 'data'}) {
  if (value is! Map) {
    throw FormatException('$source must be an object.');
  }

  final JsonMap result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry
      in value.cast<Object?, Object?>().entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$source contains a non-text key.');
    }
    result[key] = entry.value;
  }
  return result;
}

extension JsonMapValue on JsonMap {
  String requiredString(String key) {
    final value = this[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Value $key must be non-empty text.');
  }

  String? optionalString(String key) {
    final value = this[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('Value $key must be text or null.');
  }

  int requiredInt(String key) {
    final value = this[key];
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    throw FormatException('Value $key must be an integer.');
  }

  bool requiredBool(String key) {
    final value = this[key];
    if (value is bool) return value;
    if (value is int) return value != 0;
    throw FormatException('Value $key must be boolean.');
  }
}
