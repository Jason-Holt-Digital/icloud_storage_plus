// Internal helpers are public only across package library boundaries.
// ignore_for_file: public_member_api_docs

bool nativeReadBool(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value == null && !map.containsKey(key)) return false;
  if (value is bool) return value;
  throw FormatException('$key must be a bool (got: ${value.runtimeType})');
}

String nativeRequireString(Map<dynamic, dynamic> map, String key) {
  final value = _requireValue(map, key);
  if (value is String) return value;
  throw FormatException('$key must be a String (got: ${value.runtimeType})');
}

num? nativeReadNullableNum(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value == null || value is num) return value as num?;
  throw FormatException('$key must be a num or null '
      '(got: ${value.runtimeType})');
}

String? nativeReadNullableString(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('$key must be a String or null '
      '(got: ${value.runtimeType})');
}

Object? _requireValue(Map<dynamic, dynamic> map, String key) {
  if (!map.containsKey(key)) {
    throw FormatException('$key is required');
  }
  return map[key];
}

int? nativeNumToInt(num? value) => value?.toInt();

DateTime? nativeSecondsNumberToDateTime(num? value) => value == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
