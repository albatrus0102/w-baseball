import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../data/sync/sync_contracts.dart';
import '../config/app_config.dart';
import 'circuit_breaker.dart';

/// One fetched HTTP document.
class HttpDocument {
  const HttpDocument({
    required this.body,
    required this.statusCode,
    this.etag,
    this.lastModified,
    this.notModified = false,
    this.rateLimit,
  });

  final String body;
  final int statusCode;
  final String? etag;
  final DateTime? lastModified;
  final bool notModified;
  final RateLimitInfo? rateLimit;

  SyncValidators get validators =>
      SyncValidators(etag: etag, lastModified: lastModified);
}

/// Thin HTTP layer for data sources.
///
/// Adds, in one place: timeouts, cancellation, conditional requests
/// (`If-None-Match` / `If-Modified-Since`), retry with jittered backoff that
/// honours `Retry-After`, in-flight request coalescing, and per-source circuit
/// breaking. No screen and no repository ever touches Dio directly.
class WbHttpClient {
  WbHttpClient({
    required SyncConfig config,
    Dio? dio,
    Map<String, CircuitBreaker>? breakers,
  }) : _config = config,
       _dio = dio ?? _buildDio(config),
       _breakers = breakers ?? <String, CircuitBreaker>{};

  final SyncConfig _config;
  final Dio _dio;
  final Map<String, CircuitBreaker> _breakers;

  /// Coalesces identical concurrent GETs. On a slow network the home screen
  /// and the games tab can both trigger a refresh; they should share one call.
  final Map<String, Future<HttpDocument?>> _inFlight = {};

  late final BackoffPolicy _backoff = BackoffPolicy(
    initial: _config.initialBackoff,
    max: _config.maxBackoff,
  );

  /// Transport options for this client.
  ///
  /// Public so a test can build a Dio with the same settings and swap only the
  /// adapter. Constructing one by hand instead silently changes behaviour:
  /// without `ResponseType.plain` the body arrives decoded and the `String`
  /// cast fails, and without the permissive `validateStatus` a 404 throws
  /// instead of being reported as "no such file" — both of which turn into a
  /// retry loop rather than an obvious error.
  static Dio buildDio(SyncConfig config) => _buildDio(config);

  static Dio _buildDio(SyncConfig config) {
    return Dio(
      BaseOptions(
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
        sendTimeout: config.connectTimeout,
        // We parse ourselves so a wrong content-type header cannot break us.
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 3,
        // Every status is "successful" at the transport level; classification
        // happens in _classify so we can distinguish 304 / 429 / 5xx properly.
        validateStatus: (_) => true,
        headers: const <String, String>{
          'Accept': 'application/json',
          // No API keys, no credentials, no user identifiers are ever sent.
          'User-Agent': 'w-baseball-app/0.1 (+https://github.com/)',
        },
      ),
    );
  }

  CircuitBreaker breakerFor(String sourceName) => _breakers.putIfAbsent(
    sourceName,
    () => CircuitBreaker(
      name: sourceName,
      failureThreshold: _config.circuitFailureThreshold,
      resetTimeout: _config.circuitResetTimeout,
    ),
  );

  /// GET a JSON document.
  ///
  /// Returns `null` for 404 — a missing partition is normal, not a failure.
  /// Returns a document with `notModified: true` for 304.
  /// Throws [SyncException] for anything else that could not be recovered.
  Future<HttpDocument?> getDocument(
    Uri uri, {
    required String sourceName,
    SyncValidators validators = const SyncValidators(),
    CancelToken? cancelToken,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    final key = '$sourceName|$uri|${validators.etag ?? ''}';
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future =
        _getDocument(
          uri,
          sourceName: sourceName,
          validators: validators,
          cancelToken: cancelToken,
          extraHeaders: extraHeaders,
          // Block body, not an arrow. `Map.remove` returns the value it removed —
          // which here is this very future — and `whenComplete` waits on any future
          // its callback returns. Written as `=> _inFlight.remove(key)` the future
          // waits for itself and never completes, so every request through this
          // client hangs. Discarding the return value is the whole fix.
        ).whenComplete(() {
          _inFlight.remove(key);
        });

    _inFlight[key] = future;
    return future;
  }

  Future<HttpDocument?> _getDocument(
    Uri uri, {
    required String sourceName,
    required SyncValidators validators,
    CancelToken? cancelToken,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final breaker = breakerFor(sourceName);
    if (!breaker.allowsRequest) {
      throw SyncException(
        SyncFailureKind.circuitOpen,
        sourceName: sourceName,
        message:
            '이 출처는 반복 실패로 잠시 요청을 중단했습니다. '
            '다음 시도: ${breaker.nextAttemptAt?.toIso8601String() ?? '-'}',
      );
    }

    SyncException? lastError;

    for (var attempt = 1; attempt <= _config.maxAttempts; attempt++) {
      try {
        final response = await _dio.getUri<String>(
          uri,
          cancelToken: cancelToken,
          options: Options(
            headers: <String, dynamic>{
              ...validators.toRequestHeaders(),
              ...extraHeaders,
            },
          ),
        );

        final status = response.statusCode ?? 0;
        final rateLimit = _readRateLimit(response.headers);

        if (status == 304) {
          breaker.recordSuccess();
          return HttpDocument(
            body: '',
            statusCode: status,
            etag: validators.etag,
            lastModified: validators.lastModified,
            notModified: true,
            rateLimit: rateLimit,
          );
        }

        if (status == 404) {
          // Not a failure: the publisher simply has no file for this scope.
          breaker.recordSuccess();
          return null;
        }

        if (status >= 200 && status < 300) {
          breaker.recordSuccess();
          return HttpDocument(
            body: response.data ?? '',
            statusCode: status,
            etag: _header(response.headers, 'etag'),
            lastModified: _parseHttpDate(
              _header(response.headers, 'last-modified'),
            ),
            rateLimit: rateLimit,
          );
        }

        final kind = _classifyStatus(status);
        lastError = SyncException(
          kind,
          sourceName: sourceName,
          statusCode: status,
          retryAfter: rateLimit?.retryAfter,
          message: '$uri → HTTP $status',
        );

        if (!kind.isRetryable || attempt == _config.maxAttempts) {
          breaker.recordFailure(retryAfter: rateLimit?.retryAfter);
          throw lastError;
        }

        await Future<void>.delayed(
          _backoff.delayFor(attempt, retryAfter: rateLimit?.retryAfter),
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          throw SyncException(
            SyncFailureKind.cancelled,
            sourceName: sourceName,
            cause: e,
          );
        }
        final kind = _classifyDio(e);
        lastError = SyncException(
          kind,
          sourceName: sourceName,
          message: e.message,
          cause: e,
        );
        if (!kind.isRetryable || attempt == _config.maxAttempts) {
          breaker.recordFailure();
          throw lastError;
        }
        await Future<void>.delayed(_backoff.delayFor(attempt));
      }
    }

    breaker.recordFailure();
    throw lastError ??
        SyncException(SyncFailureKind.unknown, sourceName: sourceName);
  }

  static SyncFailureKind _classifyStatus(int status) => switch (status) {
    401 => SyncFailureKind.unauthorized,
    403 => SyncFailureKind.forbidden,
    404 => SyncFailureKind.notFound,
    429 => SyncFailureKind.rateLimited,
    >= 500 && < 600 => SyncFailureKind.serverError,
    _ => SyncFailureKind.unknown,
  };

  static SyncFailureKind _classifyDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return SyncFailureKind.timeout;
      case DioExceptionType.badCertificate:
        return SyncFailureKind.forbidden;
      case DioExceptionType.cancel:
        return SyncFailureKind.cancelled;
      case DioExceptionType.connectionError:
        return SyncFailureKind.network;
      case DioExceptionType.badResponse:
        return _classifyStatus(e.response?.statusCode ?? 0);
      case DioExceptionType.unknown:
        return e.error is SocketException
            ? SyncFailureKind.network
            : SyncFailureKind.unknown;
      // Dio may add cases over time; anything we do not recognise is treated
      // as unknown rather than being silently retried.
      default:
        return SyncFailureKind.unknown;
    }
  }

  static String? _header(Headers headers, String name) {
    final values = headers[name];
    if (values == null || values.isEmpty) return null;
    final v = values.first.trim();
    return v.isEmpty ? null : v;
  }

  static RateLimitInfo? _readRateLimit(Headers headers) {
    final retryAfterRaw = _header(headers, 'retry-after');
    final remaining = int.tryParse(
      _header(headers, 'x-ratelimit-remaining') ?? '',
    );
    final limit = int.tryParse(_header(headers, 'x-ratelimit-limit') ?? '');

    Duration? retryAfter;
    if (retryAfterRaw != null) {
      final seconds = int.tryParse(retryAfterRaw);
      if (seconds != null) {
        retryAfter = Duration(seconds: seconds);
      } else {
        final asDate = _parseHttpDate(retryAfterRaw);
        if (asDate != null) {
          final delta = asDate.difference(DateTime.now().toUtc());
          if (!delta.isNegative) retryAfter = delta;
        }
      }
    }

    if (retryAfter == null && remaining == null && limit == null) return null;
    return RateLimitInfo(
      remaining: remaining,
      limit: limit,
      retryAfter: retryAfter,
    );
  }

  static DateTime? _parseHttpDate(String? raw) {
    if (raw == null) return null;
    try {
      return HttpDate.parse(raw).toUtc();
    } on Object {
      return DateTime.tryParse(raw)?.toUtc();
    }
  }

  void close() {
    _dio.close(force: true);
    _inFlight.clear();
  }
}
