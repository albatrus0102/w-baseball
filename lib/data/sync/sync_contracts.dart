import 'package:meta/meta.dart';

/// Transport-neutral sync contracts.
///
/// These types are the seam between "where data comes from" and "what the app
/// does with it". A static JSON manifest, a bundled seed asset, a REST API,
/// and a GraphQL API all speak this vocabulary, so adding an official API
/// later means writing one adapter — not touching repositories or screens.

/// What kind of data a page carries relative to what we already hold.
enum SyncPayloadKind {
  /// The complete current set for the requested scope. Anything absent from a
  /// snapshot is a tombstone candidate.
  snapshot,

  /// Only records changed since [SyncRequest.updatedSince]. Absence means
  /// "unchanged", never "deleted".
  delta,
}

/// Cursor for paginated sources. Opaque to callers: a REST source may put an
/// offset in it, a GraphQL source a base64 node id.
@immutable
class SyncCursor {
  const SyncCursor(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SyncCursor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SyncCursor($value)';
}

/// Concurrency / caching validators carried across a sync.
@immutable
class SyncValidators {
  const SyncValidators({this.etag, this.lastModified});

  final String? etag;
  final DateTime? lastModified;

  bool get isEmpty => etag == null && lastModified == null;

  Map<String, String> toRequestHeaders() {
    final headers = <String, String>{};
    final tag = etag;
    if (tag != null && tag.isNotEmpty) headers['If-None-Match'] = tag;
    final since = lastModified;
    if (since != null) headers['If-Modified-Since'] = _httpDate(since.toUtc());
    return headers;
  }

  static const _days = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _httpDate(DateTime utc) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${_days[utc.weekday - 1]}, ${two(utc.day)} ${_months[utc.month - 1]} '
        '${utc.year} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
  }
}

/// A request for one page of one entity type.
@immutable
class SyncRequest {
  const SyncRequest({
    this.cursor,
    this.pageNumber,
    this.pageSize = 100,
    this.updatedSince,
    this.validators = const SyncValidators(),
    this.scopeKey,
  });

  /// Cursor-based pagination. Mutually exclusive with [pageNumber] in
  /// practice; adapters use whichever their transport supports.
  final SyncCursor? cursor;

  /// Page-number pagination, 1-based.
  final int? pageNumber;

  final int pageSize;

  /// Incremental sync watermark. Null asks for a full snapshot.
  final DateTime? updatedSince;

  final SyncValidators validators;

  /// Free-form scope discriminator, e.g. `2026-08` for a month of games.
  final String? scopeKey;

  bool get isIncremental => updatedSince != null;

  SyncRequest nextPage(SyncCursor? next) => SyncRequest(
    cursor: next,
    pageNumber: next == null && pageNumber != null ? pageNumber! + 1 : null,
    pageSize: pageSize,
    updatedSince: updatedSince,
    validators: validators,
    scopeKey: scopeKey,
  );

  SyncRequest copyWith({
    SyncCursor? cursor,
    int? pageNumber,
    int? pageSize,
    DateTime? updatedSince,
    SyncValidators? validators,
    String? scopeKey,
  }) {
    return SyncRequest(
      cursor: cursor ?? this.cursor,
      pageNumber: pageNumber ?? this.pageNumber,
      pageSize: pageSize ?? this.pageSize,
      updatedSince: updatedSince ?? this.updatedSince,
      validators: validators ?? this.validators,
      scopeKey: scopeKey ?? this.scopeKey,
    );
  }
}

/// Narrows a game sync to a manageable slice. We never ask a source for
/// "all games ever" — requests are scoped by month, season, or competition.
@immutable
class GameSyncRequest extends SyncRequest {
  const GameSyncRequest({
    this.month,
    this.seasonId,
    this.competitionId,
    this.teamId,
    super.cursor,
    super.pageNumber,
    super.pageSize,
    super.updatedSince,
    super.validators,
    super.scopeKey,
  });

  /// `yyyy-MM`. The primary partition for the static JSON layout.
  final String? month;
  final String? seasonId;
  final String? competitionId;
  final String? teamId;

  @override
  GameSyncRequest nextPage(SyncCursor? next) => GameSyncRequest(
    month: month,
    seasonId: seasonId,
    competitionId: competitionId,
    teamId: teamId,
    cursor: next,
    pageNumber: next == null && pageNumber != null ? pageNumber! + 1 : null,
    pageSize: pageSize,
    updatedSince: updatedSince,
    validators: validators,
    scopeKey: scopeKey,
  );
}

/// Rate-limit state reported by a source.
@immutable
class RateLimitInfo {
  const RateLimitInfo({
    this.remaining,
    this.limit,
    this.retryAfter,
    this.resetAt,
  });

  final int? remaining;
  final int? limit;

  /// Honoured verbatim by the retry policy; overrides computed backoff.
  final Duration? retryAfter;
  final DateTime? resetAt;

  bool get isThrottled =>
      retryAfter != null || (remaining != null && remaining! <= 0);
}

/// Severity of a per-record problem.
enum SyncIssueSeverity {
  /// Record accepted, but something was odd (unknown enum value, say).
  warning,

  /// This one record was quarantined. The rest of the page still applies.
  recordRejected,

  /// The whole page/source failed.
  sourceFailed,
}

@immutable
class SyncIssue {
  const SyncIssue({
    required this.severity,
    required this.sourceName,
    required this.entityType,
    required this.message,
    this.sourceRecordId,
    this.field,
  });

  final SyncIssueSeverity severity;
  final String sourceName;
  final String entityType;
  final String message;
  final String? sourceRecordId;
  final String? field;

  @override
  String toString() =>
      '[${severity.name}] $sourceName/$entityType'
      '${sourceRecordId == null ? '' : '#$sourceRecordId'}'
      '${field == null ? '' : '.$field'}: $message';
}

/// One page of DTOs plus everything the engine needs to decide what to do next.
@immutable
class SyncPage<T> {
  const SyncPage({
    required this.items,
    required this.sourceName,
    required this.payloadKind,
    this.hasMore = false,
    this.nextCursor,
    this.schemaVersion = 1,
    this.dataVersion,
    this.validators = const SyncValidators(),
    this.rateLimit,
    this.issues = const <SyncIssue>[],
    this.notModified = false,
    this.generatedAt,
    this.tombstonedSourceRecordIds = const <String>[],
  });

  /// Records that survived validation. Malformed ones are in [issues].
  final List<T> items;

  final String sourceName;
  final SyncPayloadKind payloadKind;
  final bool hasMore;
  final SyncCursor? nextCursor;

  /// Contract version of this payload. Checked against `DataContractConfig`.
  final int schemaVersion;

  /// Publisher's build id, e.g. `2026.08.30.1`.
  final String? dataVersion;

  final SyncValidators validators;
  final RateLimitInfo? rateLimit;

  /// Warnings and per-record rejections. A page can be partially successful.
  final List<SyncIssue> issues;

  /// 304: nothing changed, keep what we have.
  final bool notModified;

  final DateTime? generatedAt;

  /// Records the source explicitly says are gone. Distinct from "absent from
  /// a delta", which means unchanged.
  final List<String> tombstonedSourceRecordIds;

  bool get isEmpty => items.isEmpty;

  bool get hasRejections =>
      issues.any((i) => i.severity == SyncIssueSeverity.recordRejected);

  /// An empty page factory for sources that legitimately have nothing.
  static SyncPage<T> empty<T>(String sourceName) => SyncPage<T>(
    items: const [],
    sourceName: sourceName,
    payloadKind: SyncPayloadKind.delta,
  );

  static SyncPage<T> unchanged<T>(
    String sourceName,
    SyncValidators validators,
  ) => SyncPage<T>(
    items: const [],
    sourceName: sourceName,
    payloadKind: SyncPayloadKind.delta,
    validators: validators,
    notModified: true,
  );

  SyncPage<R> mapItems<R>(R Function(T) transform) => SyncPage<R>(
    items: items.map(transform).toList(growable: false),
    sourceName: sourceName,
    payloadKind: payloadKind,
    hasMore: hasMore,
    nextCursor: nextCursor,
    schemaVersion: schemaVersion,
    dataVersion: dataVersion,
    validators: validators,
    rateLimit: rateLimit,
    issues: issues,
    notModified: notModified,
    generatedAt: generatedAt,
    tombstonedSourceRecordIds: tombstonedSourceRecordIds,
  );
}

/// What went wrong at the source level.
enum SyncFailureKind {
  none,
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  rateLimited,
  serverError,
  schemaUnsupported,
  malformedPayload,
  checksumMismatch,
  /// Configured, reachable, and simply not built yet.
  ///
  /// Kept distinct from [unauthorized] because the user-facing sentences are
  /// opposites: one blames the publisher for withholding access, the other
  /// admits the app has not implemented the connection. Reporting a missing
  /// adapter as an access problem sends people to complain to the wrong party.
  notImplemented,
  circuitOpen,
  cancelled,
  unknown;

  /// Whether retrying the same request could plausibly succeed.
  bool get isRetryable => switch (this) {
    SyncFailureKind.network ||
    SyncFailureKind.timeout ||
    SyncFailureKind.rateLimited ||
    SyncFailureKind.serverError ||
    // A hash mismatch is usually transient: a CDN edge still serving the
    // previous file, or an upload caught half-finished. Retrying can get the
    // right bytes, which is why this is not lumped in with malformedPayload.
    SyncFailureKind.checksumMismatch => true,
    _ => false,
  };

  String get messageKo => switch (this) {
    SyncFailureKind.none => '',
    SyncFailureKind.network => '네트워크에 연결할 수 없습니다.',
    SyncFailureKind.timeout => '응답 시간이 초과되었습니다.',
    SyncFailureKind.unauthorized => '데이터 접근 권한이 없습니다.',
    SyncFailureKind.forbidden => '데이터 접근이 거부되었습니다.',
    SyncFailureKind.notFound => '요청한 데이터를 찾을 수 없습니다.',
    SyncFailureKind.rateLimited => '요청이 많아 잠시 후 다시 시도합니다.',
    SyncFailureKind.serverError => '데이터 서버에 문제가 있습니다.',
    SyncFailureKind.schemaUnsupported => '앱이 지원하지 않는 데이터 버전입니다. 앱을 업데이트해 주세요.',
    SyncFailureKind.malformedPayload => '데이터 형식이 올바르지 않습니다.',
    SyncFailureKind.checksumMismatch => '받은 파일이 배포 목록과 일치하지 않아 적용하지 않았습니다.',
    SyncFailureKind.notImplemented => '이 데이터 출처는 아직 앱에 연결되지 않았습니다.',
    SyncFailureKind.circuitOpen => '해당 출처는 잠시 후 다시 시도합니다.',
    SyncFailureKind.cancelled => '동기화가 취소되었습니다.',
    SyncFailureKind.unknown => '알 수 없는 오류가 발생했습니다.',
  };
}

/// Raised by data sources. Carries enough for the engine to decide between
/// retry, back off, quarantine, and open-circuit.
class SyncException implements Exception {
  SyncException(
    this.kind, {
    required this.sourceName,
    this.message,
    this.statusCode,
    this.retryAfter,
    this.receivedSchemaVersion,
    this.cause,
  });

  final SyncFailureKind kind;
  final String sourceName;
  final String? message;
  final int? statusCode;
  final Duration? retryAfter;
  final int? receivedSchemaVersion;
  final Object? cause;

  bool get isRetryable => kind.isRetryable;

  @override
  String toString() =>
      'SyncException(${kind.name}, source=$sourceName, status=$statusCode, '
      'message=${message ?? kind.messageKo})';
}

/// What a single scope's sync accomplished.
@immutable
class SyncResult {
  const SyncResult({
    required this.sourceName,
    required this.startedAt,
    required this.finishedAt,
    this.inserted = 0,
    this.updated = 0,
    this.tombstoned = 0,
    this.unchanged = 0,
    this.pagesFetched = 0,
    this.issues = const <SyncIssue>[],
    this.failure = SyncFailureKind.none,
    this.failureMessage,
    this.dataVersion,
    this.skippedBecauseNotModified = false,
  });

  final String sourceName;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int inserted;
  final int updated;
  final int tombstoned;
  final int unchanged;
  final int pagesFetched;
  final List<SyncIssue> issues;
  final SyncFailureKind failure;
  final String? failureMessage;
  final String? dataVersion;
  final bool skippedBecauseNotModified;

  bool get isSuccess => failure == SyncFailureKind.none;

  /// True when we applied some data but also rejected some. The UI shows
  /// "일부 데이터만 갱신됨" for this case rather than a plain success.
  bool get isPartial =>
      isSuccess && issues.any((i) => i.severity != SyncIssueSeverity.warning);

  int get changedCount => inserted + updated + tombstoned;

  Duration get duration => finishedAt.difference(startedAt);

  static SyncResult failed({
    required String sourceName,
    required SyncFailureKind kind,
    required DateTime startedAt,
    required DateTime finishedAt,
    String? message,
    List<SyncIssue> issues = const <SyncIssue>[],
  }) {
    return SyncResult(
      sourceName: sourceName,
      startedAt: startedAt,
      finishedAt: finishedAt,
      failure: kind,
      failureMessage: message ?? kind.messageKo,
      issues: issues,
    );
  }
}

/// Aggregate of every source touched by one refresh.
@immutable
class SyncReport {
  const SyncReport({required this.results, required this.finishedAt});

  final List<SyncResult> results;
  final DateTime finishedAt;

  /// One source failing must not read as a total failure — that is the whole
  /// point of per-source isolation.
  bool get anySucceeded => results.any((r) => r.isSuccess);
  bool get allSucceeded =>
      results.isNotEmpty && results.every((r) => r.isSuccess);
  bool get anyFailed => results.any((r) => !r.isSuccess);

  int get totalChanged => results.fold(0, (acc, r) => acc + r.changedCount);

  List<SyncResult> get failures =>
      results.where((r) => !r.isSuccess).toList(growable: false);

  static SyncReport empty(DateTime at) =>
      SyncReport(results: const [], finishedAt: at);
}

/// Which slice of data to refresh.
@immutable
class GameSyncScope {
  const GameSyncScope({
    this.months = const <String>[],
    this.seasonIds = const <String>[],
    this.competitionIds = const <String>[],
    this.fullRefresh = false,
  });

  /// `yyyy-MM` partitions.
  final List<String> months;
  final List<String> seasonIds;
  final List<String> competitionIds;

  /// Ignore stored watermarks and re-request snapshots.
  final bool fullRefresh;

  /// The default pull: last month, this month, next month. Enough to answer
  /// "recent results" and "next fixture" without downloading a whole season.
  factory GameSyncScope.aroundNow(DateTime now) {
    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
    final base = DateTime(now.year, now.month);
    return GameSyncScope(
      months: <String>[
        key(DateTime(base.year, base.month - 1)),
        key(base),
        key(DateTime(base.year, base.month + 1)),
      ],
    );
  }

  bool get isEmpty =>
      months.isEmpty && seasonIds.isEmpty && competitionIds.isEmpty;
}
