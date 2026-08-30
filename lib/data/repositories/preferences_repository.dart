import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_system/tokens.dart';
import '../models/audience.dart';

/// Device-local settings.
///
/// Everything here is a preference, not content, so it lives in
/// `shared_preferences` rather than SQLite: it is tiny, read synchronously at
/// startup, and must survive a "clear synced data" wipe of the database.
///
/// Nothing in this store identifies the user, and none of it is transmitted.
abstract interface class PreferencesRepository {
  AudiencePreference get audience;

  Stream<AudiencePreference> watchAudience();

  Future<void> saveAudience(AudiencePreference preference);

  NotificationPreference get notifications;

  Stream<NotificationPreference> watchNotifications();

  Future<void> saveNotifications(NotificationPreference preference);

  /// Recent search terms, stored on the device only, clearable by the user.
  List<String> get recentSearches;

  Future<void> addRecentSearch(String term);

  Future<void> clearRecentSearches();

  DateTime? get lastSuccessfulSyncAt;

  Future<void> setLastSuccessfulSyncAt(DateTime value);

  Future<void> reset();
}

class SharedPrefsRepository implements PreferencesRepository {
  SharedPrefsRepository(this._prefs) {
    _audience = _readAudience();
    _notifications = _readNotifications();
  }

  static const _kMode = 'audience.mode';
  static const _kSpoiler = 'audience.spoiler';
  static const _kRegionCode = 'audience.regionCode';
  static const _kRegionLabel = 'audience.regionLabel';
  static const _kBeginner = 'audience.beginnerExplanations';
  static const _kOnboardingDone = 'audience.onboardingCompleted';
  static const _kOnboardingSkipped = 'audience.onboardingSkipped';
  static const _kModuleOrder = 'audience.homeModuleOrder';
  static const _kCollapsed = 'audience.collapsedModules';
  static const _kRadius = 'audience.searchRadiusKm';
  static const _kUseLocation = 'audience.useDeviceLocation';
  static const _kDensity = 'audience.density';

  static const _kNotifEnabled = 'notif.enabled';
  static const _kQuietStart = 'notif.quietStart';
  static const _kQuietEnd = 'notif.quietEnd';
  static const _kNotifSpoilers = 'notif.allowSpoilers';
  static const _kPermissionAsked = 'notif.permissionRequested';

  static const _kRecentSearches = 'search.recent';
  static const _kLastSync = 'sync.lastSuccessfulAt';

  static const int _maxRecentSearches = 8;

  final SharedPreferences _prefs;

  late AudiencePreference _audience;
  late NotificationPreference _notifications;

  final _audienceController = StreamController<AudiencePreference>.broadcast();
  final _notificationsController =
      StreamController<NotificationPreference>.broadcast();

  static Future<SharedPrefsRepository> create() async =>
      SharedPrefsRepository(await SharedPreferences.getInstance());

  @override
  AudiencePreference get audience => _audience;

  @override
  Stream<AudiencePreference> watchAudience() async* {
    yield _audience;
    yield* _audienceController.stream;
  }

  AudiencePreference _readAudience() {
    return AudiencePreference(
      mode: AudienceMode.parse(_prefs.getString(_kMode)),
      spoilerPolicy: SpoilerPolicy.parse(_prefs.getString(_kSpoiler)),
      regionCode: _prefs.getString(_kRegionCode),
      regionLabel: _prefs.getString(_kRegionLabel),
      showBeginnerExplanations: _prefs.getBool(_kBeginner) ?? true,
      onboardingCompleted: _prefs.getBool(_kOnboardingDone) ?? false,
      onboardingSkipped: _prefs.getBool(_kOnboardingSkipped) ?? false,
      homeModuleOrder: _prefs.getStringList(_kModuleOrder) ?? const <String>[],
      collapsedModules: (_prefs.getStringList(_kCollapsed) ?? const <String>[])
          .toSet(),
      searchRadiusKm: _prefs.getInt(_kRadius) ?? 40,
      useDeviceLocation: _prefs.getBool(_kUseLocation) ?? false,
      // Absent means "follow the mode", which is not the same as a stored
      // `comfortable` — so this stays null rather than defaulting.
      densityOverride: _prefs.containsKey(_kDensity)
          ? WbDensity.parse(_prefs.getString(_kDensity))
          : null,
    );
  }

  @override
  Future<void> saveAudience(AudiencePreference p) async {
    await _prefs.setString(_kMode, p.mode.wireValue);
    await _prefs.setString(_kSpoiler, p.spoilerPolicy.wireValue);
    if (p.regionCode == null) {
      await _prefs.remove(_kRegionCode);
      await _prefs.remove(_kRegionLabel);
    } else {
      await _prefs.setString(_kRegionCode, p.regionCode!);
      if (p.regionLabel != null) {
        await _prefs.setString(_kRegionLabel, p.regionLabel!);
      }
    }
    await _prefs.setBool(_kBeginner, p.showBeginnerExplanations);
    await _prefs.setBool(_kOnboardingDone, p.onboardingCompleted);
    await _prefs.setBool(_kOnboardingSkipped, p.onboardingSkipped);
    await _prefs.setStringList(_kModuleOrder, p.homeModuleOrder);
    await _prefs.setStringList(_kCollapsed, p.collapsedModules.toList());
    await _prefs.setInt(_kRadius, p.searchRadiusKm);
    await _prefs.setBool(_kUseLocation, p.useDeviceLocation);
    if (p.densityOverride == null) {
      await _prefs.remove(_kDensity);
    } else {
      await _prefs.setString(_kDensity, p.densityOverride!.wireValue);
    }
    _audience = p;
    _audienceController.add(p);
  }

  @override
  NotificationPreference get notifications => _notifications;

  @override
  Stream<NotificationPreference> watchNotifications() async* {
    yield _notifications;
    yield* _notificationsController.stream;
  }

  NotificationPreference _readNotifications() {
    final raw = _prefs.getStringList(_kNotifEnabled) ?? const <String>[];
    final enabled = raw
        .map(NotificationCategory.parse)
        .whereType<NotificationCategory>()
        .toSet();
    final start = _prefs.getInt(_kQuietStart);
    final end = _prefs.getInt(_kQuietEnd);
    return NotificationPreference(
      enabled: enabled,
      quietHoursStartMinute: start == -1 ? null : start,
      quietHoursEndMinute: end == -1 ? null : end,
      allowSpoilersInNotifications: _prefs.getBool(_kNotifSpoilers) ?? false,
      permissionRequested: _prefs.getBool(_kPermissionAsked) ?? false,
    );
  }

  @override
  Future<void> saveNotifications(NotificationPreference p) async {
    await _prefs.setStringList(
      _kNotifEnabled,
      p.enabled.map((c) => c.wireValue).toList(),
    );
    await _prefs.setInt(_kQuietStart, p.quietHoursStartMinute ?? -1);
    await _prefs.setInt(_kQuietEnd, p.quietHoursEndMinute ?? -1);
    await _prefs.setBool(_kNotifSpoilers, p.allowSpoilersInNotifications);
    await _prefs.setBool(_kPermissionAsked, p.permissionRequested);
    _notifications = p;
    _notificationsController.add(p);
  }

  @override
  List<String> get recentSearches =>
      _prefs.getStringList(_kRecentSearches) ?? const <String>[];

  @override
  Future<void> addRecentSearch(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    final current = recentSearches.toList()
      ..removeWhere((t) => t == trimmed)
      ..insert(0, trimmed);
    if (current.length > _maxRecentSearches) {
      current.removeRange(_maxRecentSearches, current.length);
    }
    await _prefs.setStringList(_kRecentSearches, current);
  }

  @override
  Future<void> clearRecentSearches() => _prefs.remove(_kRecentSearches);

  @override
  DateTime? get lastSuccessfulSyncAt {
    final raw = _prefs.getString(_kLastSync);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> setLastSuccessfulSyncAt(DateTime value) =>
      _prefs.setString(_kLastSync, value.toUtc().toIso8601String());

  @override
  Future<void> reset() async {
    await _prefs.clear();
    _audience = _readAudience();
    _notifications = _readNotifications();
    _audienceController.add(_audience);
    _notificationsController.add(_notifications);
  }

  void dispose() {
    _audienceController.close();
    _notificationsController.close();
  }
}

/// Persists per-file sync validators through `shared_preferences`, so the
/// static manifest source has somewhere to remember ETags between launches
/// without depending on the database.
class PrefsValidatorStoreCodec {
  const PrefsValidatorStoreCodec._();

  static String encode({
    String? etag,
    DateTime? lastModified,
    String? sha256,
  }) => jsonEncode(<String, dynamic>{
    'etag': ?etag,
    'lastModified': ?lastModified?.toUtc().toIso8601String(),
    'sha256': ?sha256,
  });

  static ({String? etag, DateTime? lastModified, String? sha256}) decode(
    String? raw,
  ) {
    if (raw == null || raw.isEmpty) {
      return (etag: null, lastModified: null, sha256: null);
    }
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return (etag: null, lastModified: null, sha256: null);
      final lm = map['lastModified'];
      return (
        etag: map['etag'] as String?,
        lastModified: lm is String ? DateTime.tryParse(lm)?.toUtc() : null,
        sha256: map['sha256'] as String?,
      );
    } on FormatException {
      return (etag: null, lastModified: null, sha256: null);
    }
  }
}
