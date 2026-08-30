/// Thrown when a record cannot be understood well enough to be trusted.
///
/// The sync engine catches this *per record*, records a
/// `SyncIssueSeverity.recordRejected` issue, and keeps processing the rest of
/// the page. One bad row never fails a whole feed.
class DtoValidationException implements Exception {
  DtoValidationException(this.field, this.reason, {this.recordId});

  final String field;
  final String reason;
  final String? recordId;

  @override
  String toString() =>
      'DtoValidationException(${recordId ?? '?'}.$field: $reason)';
}

/// Tolerant reader over a decoded JSON map.
///
/// Two rules, applied everywhere:
///  * Unknown keys are ignored. A source adding fields must never break us.
///  * A missing or unusable *required* field rejects that one record loudly,
///    rather than silently defaulting to something that looks like real data.
class JsonReader {
  JsonReader(this._map, {this.recordId});

  factory JsonReader.of(Object? value, {String? recordId}) {
    if (value is Map<String, dynamic>) {
      return JsonReader(value, recordId: recordId);
    }
    if (value is Map) {
      return JsonReader(
        value.map((k, v) => MapEntry(k.toString(), v)),
        recordId: recordId,
      );
    }
    throw DtoValidationException('<root>', 'object가 아닙니다', recordId: recordId);
  }

  final Map<String, dynamic> _map;
  final String? recordId;

  bool has(String key) => _map.containsKey(key) && _map[key] != null;

  Never _reject(String field, String reason) =>
      throw DtoValidationException(field, reason, recordId: recordId);

  // Strings ---------------------------------------------------------------

  String requireString(String key) {
    final v = optionalString(key);
    if (v == null || v.isEmpty) _reject(key, '필수 문자열이 비어 있습니다');
    return v;
  }

  String? optionalString(String key) {
    final raw = _map[key];
    if (raw == null) return null;
    if (raw is String) {
      final t = raw.trim();
      return t.isEmpty ? null : t;
    }
    if (raw is num || raw is bool) return raw.toString();
    return null;
  }

  /// Required URL with a scheme we are willing to open.
  String requireUrl(String key) {
    final v = requireString(key);
    if (!_isAcceptableUrl(v)) _reject(key, 'http(s) URL이 아닙니다: $v');
    return v;
  }

  String? optionalUrl(String key) {
    final v = optionalString(key);
    if (v == null) return null;
    return _isAcceptableUrl(v) ? v : null;
  }

  static bool _isAcceptableUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  // Numbers ---------------------------------------------------------------

  int requireInt(String key) {
    final v = optionalInt(key);
    if (v == null) _reject(key, '필수 정수가 없습니다');
    return v;
  }

  int? optionalInt(String key) {
    final raw = _map[key];
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is double) return raw.isFinite ? raw.round() : null;
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  double? optionalDouble(String key) {
    final raw = _map[key];
    if (raw == null) return null;
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    if (raw is String) {
      final parsed = double.tryParse(raw.trim());
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }
    return null;
  }

  bool optionalBool(String key, {bool fallback = false}) {
    final raw = _map[key];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final t = raw.trim().toLowerCase();
      if (t == 'true' || t == '1' || t == 'y') return true;
      if (t == 'false' || t == '0' || t == 'n') return false;
    }
    return fallback;
  }

  // Dates -----------------------------------------------------------------

  /// Requires an ISO-8601 instant that carries a zone designator.
  ///
  /// A wall-clock string with no offset is rejected rather than guessed at:
  /// a game time without a time zone is not a usable game time.
  DateTime requireInstant(String key) {
    final v = optionalInstant(key);
    if (v == null) {
      _reject(key, '시간대를 포함한 ISO-8601 시각이 필요합니다');
    }
    return v;
  }

  DateTime? optionalInstant(String key) {
    final raw = optionalString(key);
    if (raw == null) return null;
    if (!_hasZoneDesignator(raw)) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed?.toUtc();
  }

  /// A plain calendar date (`yyyy-MM-dd`), stored at UTC midnight.
  DateTime? optionalDate(String key) {
    final raw = optionalString(key);
    if (raw == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (match == null) return null;
    return DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static bool _hasZoneDesignator(String value) {
    if (value.endsWith('Z') || value.endsWith('z')) return true;
    // Look for +HH:MM / -HH:MM after the time portion.
    final timeIndex = value.indexOf('T');
    if (timeIndex < 0) return false;
    final tail = value.substring(timeIndex);
    return RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(tail);
  }

  // Collections -----------------------------------------------------------

  List<String> stringList(String key) {
    final raw = _map[key];
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e is String ? e.trim() : e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// Nullable ints, preserving `null` entries — used for innings where a team
  /// did not bat, which is meaningfully different from scoring zero.
  List<int?> nullableIntList(String key) {
    final raw = _map[key];
    if (raw is! List) return const <int?>[];
    return raw
        .map<int?>((e) {
          if (e == null) return null;
          if (e is int) return e;
          if (e is double) return e.isFinite ? e.round() : null;
          if (e is String) {
            final t = e.trim();
            if (t.isEmpty || t == '-' || t == 'x' || t == 'X') return null;
            return int.tryParse(t);
          }
          return null;
        })
        .toList(growable: false);
  }

  List<JsonReader> objectList(String key) {
    final raw = _map[key];
    if (raw is! List) return const <JsonReader>[];
    final out = <JsonReader>[];
    for (final entry in raw) {
      if (entry is Map) {
        out.add(JsonReader.of(entry, recordId: recordId));
      }
    }
    return out;
  }

  JsonReader? optionalObject(String key) {
    final raw = _map[key];
    if (raw is Map) return JsonReader.of(raw, recordId: recordId);
    return null;
  }

  /// The keys the source sent that we do not consume. Logged as a warning so
  /// contract drift is visible without breaking anything.
  List<String> unknownKeys(Set<String> known) =>
      _map.keys.where((k) => !known.contains(k)).toList(growable: false);
}
