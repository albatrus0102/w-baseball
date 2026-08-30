import 'dart:math';

/// Per-source failure isolation.
///
/// One flaky feed must never stall the whole refresh or the app. After
/// [failureThreshold] consecutive failures a source's circuit opens and every
/// call fails fast until [resetTimeout] elapses, at which point one trial call
/// is allowed through (half-open). A success closes it again.
enum CircuitState { closed, open, halfOpen }

class CircuitBreaker {
  CircuitBreaker({
    required this.name,
    this.failureThreshold = 4,
    this.resetTimeout = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String name;
  final int failureThreshold;
  final Duration resetTimeout;
  final DateTime Function() _clock;

  int _consecutiveFailures = 0;
  DateTime? _openedAt;

  /// Set from a `Retry-After` header; the circuit stays shut at least this long.
  DateTime? _retryNotBefore;

  CircuitState get state {
    final openedAt = _openedAt;
    if (openedAt == null) return CircuitState.closed;
    final now = _clock();
    final blockedUntil = _retryNotBefore;
    if (blockedUntil != null && now.isBefore(blockedUntil)) {
      return CircuitState.open;
    }
    return now.difference(openedAt) >= resetTimeout
        ? CircuitState.halfOpen
        : CircuitState.open;
  }

  bool get allowsRequest => state != CircuitState.open;

  int get consecutiveFailures => _consecutiveFailures;

  /// When the caller may try again, or null if it may try now.
  DateTime? get nextAttemptAt {
    final openedAt = _openedAt;
    if (openedAt == null) return null;
    final afterReset = openedAt.add(resetTimeout);
    final explicit = _retryNotBefore;
    if (explicit == null) return afterReset;
    return explicit.isAfter(afterReset) ? explicit : afterReset;
  }

  void recordSuccess() {
    _consecutiveFailures = 0;
    _openedAt = null;
    _retryNotBefore = null;
  }

  void recordFailure({Duration? retryAfter}) {
    _consecutiveFailures++;
    if (retryAfter != null) {
      _retryNotBefore = _clock().add(retryAfter);
      // An explicit Retry-After is a direct instruction; respect it even if we
      // are nowhere near the failure threshold.
      _openedAt ??= _clock();
    }
    if (_consecutiveFailures >= failureThreshold) {
      _openedAt = _clock();
    }
  }

  void reset() {
    _consecutiveFailures = 0;
    _openedAt = null;
    _retryNotBefore = null;
  }
}

/// Exponential backoff with full jitter.
///
/// Jitter matters because every install refreshes on launch; without it, a
/// transient outage produces synchronised retry spikes against a static host.
class BackoffPolicy {
  const BackoffPolicy({
    this.initial = const Duration(milliseconds: 600),
    this.max = const Duration(seconds: 20),
    this.multiplier = 2.0,
  });

  final Duration initial;
  final Duration max;
  final double multiplier;

  /// [attempt] is 1-based. A server-supplied [retryAfter] always wins.
  Duration delayFor(int attempt, {Duration? retryAfter, Random? random}) {
    if (retryAfter != null) {
      return retryAfter > max ? max : retryAfter;
    }
    final rng = random ?? _shared;
    final exponential =
        initial.inMilliseconds * pow(multiplier, (attempt - 1).clamp(0, 16));
    final capped = min(exponential.toDouble(), max.inMilliseconds.toDouble());
    // Full jitter: uniform in [0, capped].
    return Duration(milliseconds: (rng.nextDouble() * capped).round());
  }

  static final Random _shared = Random();
}
