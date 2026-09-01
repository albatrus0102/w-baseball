import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Platform integration behind interfaces.
///
/// Every OS-specific call in the app goes through one of these. Screens depend
/// on the interface, never on `Platform.isAndroid` or a channel name, so the
/// iOS port is a matter of adding implementations here — EventKit instead of
/// CalendarContract, Apple Maps alongside Kakao/Naver — with no UI changes.

/// An event the user wants in their own calendar.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.startUtc,
    required this.endUtc,
    this.location,
    this.description,
    this.url,
  });

  final String title;
  final DateTime startUtc;
  final DateTime endUtc;
  final String? location;
  final String? description;
  final String? url;
}

abstract interface class CalendarService {
  /// True when this platform can hand an event to a calendar app.
  bool get isSupported;

  /// Opens the system calendar's "new event" screen pre-filled.
  ///
  /// Deliberately *not* a silent write: opening the composer needs no calendar
  /// permission and leaves the user in control of which calendar it lands in.
  Future<bool> addEvent(CalendarEvent event);
}

/// Android implementation via `Intent.ACTION_INSERT` on CalendarContract.
///
/// Written as a first-party MethodChannel rather than taking a package
/// dependency: it is ~30 lines of Kotlin, needs no runtime permission, and
/// keeps the Android-specific surface inside this project where the iOS port
/// can mirror it.
class AndroidCalendarService implements CalendarService {
  const AndroidCalendarService();

  static const MethodChannel _channel = MethodChannel(
    'kr.wbaseball.w_baseball/calendar',
  );

  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> addEvent(CalendarEvent event) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('insertEvent', {
        'title': event.title,
        'beginTime': event.startUtc.millisecondsSinceEpoch,
        'endTime': event.endUtc.millisecondsSinceEpoch,
        'location': event.location,
        'description': event.description,
      });
      return result ?? false;
    } on PlatformException {
      // No calendar app installed, or the intent was refused. The caller
      // surfaces a message rather than the app appearing to do nothing.
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Used on platforms with no implementation yet (and in tests).
class UnsupportedCalendarService implements CalendarService {
  const UnsupportedCalendarService();

  @override
  bool get isSupported => false;

  @override
  Future<bool> addEvent(CalendarEvent event) async => false;
}

/// Opens directions in whatever maps app the user has.
abstract interface class MapsService {
  /// Starts navigation to a coordinate, falling back to an address search when
  /// coordinates are unknown. Returns false when nothing could handle it.
  Future<bool> openDirections({
    double? latitude,
    double? longitude,
    String? address,
    String? label,
  });
}

class UrlMapsService implements MapsService {
  const UrlMapsService();

  @override
  Future<bool> openDirections({
    double? latitude,
    double? longitude,
    String? address,
    String? label,
  }) async {
    final hasCoords = latitude != null && longitude != null;
    if (!hasCoords && (address == null || address.trim().isEmpty)) return false;

    // Try the platform's geo/maps handler first; it lets the user pick their
    // preferred maps app rather than us choosing one for them.
    final candidates = <Uri>[];

    if (hasCoords) {
      if (!kIsWeb && Platform.isAndroid) {
        // `geo:` with a query keeps the label visible in the picker.
        final q = label == null
            ? '$latitude,$longitude'
            : '$latitude,$longitude(${Uri.encodeComponent(label)})';
        candidates.add(Uri.parse('geo:$latitude,$longitude?q=$q'));
      }
      candidates.add(
        Uri.https('www.google.com', '/maps/dir/', <String, String>{
          'api': '1',
          'destination': '$latitude,$longitude',
        }),
      );
    } else {
      final query = address!.trim();
      if (!kIsWeb && Platform.isAndroid) {
        candidates.add(Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}'));
      }
      candidates.add(
        Uri.https('www.google.com', '/maps/search/', <String, String>{
          'api': '1',
          'query': query,
        }),
      );
    }

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            return true;
          }
        }
      } on PlatformException {
        continue;
      } on MissingPluginException {
        return false;
      }
    }
    return false;
  }
}

abstract interface class SharingService {
  Future<void> shareText({required String text, String? subject});

  /// Hands one or more files to the OS share sheet — the 내보내기 mechanism
  /// for 출전 일지. No storage permission is requested: `share_plus` reads
  /// the files itself and only the target app the user picks ever receives
  /// them, which is what keeps the privacy policy's permission table
  /// unchanged by this feature.
  Future<void> shareFiles({
    required List<XFile> files,
    String? text,
    String? subject,
  });
}

class PlatformSharingService implements SharingService {
  const PlatformSharingService();

  @override
  Future<void> shareText({required String text, String? subject}) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    } on MissingPluginException {
      // Nothing to share with (headless test host). Silently ignore.
    }
  }

  @override
  Future<void> shareFiles({
    required List<XFile> files,
    String? text,
    String? subject,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: files, text: text, subject: subject),
      );
    } on MissingPluginException {
      // Nothing to share with (headless test host). Silently ignore.
    }
  }
}

class NoopSharingService implements SharingService {
  const NoopSharingService();

  @override
  Future<void> shareText({required String text, String? subject}) async {}

  @override
  Future<void> shareFiles({
    required List<XFile> files,
    String? text,
    String? subject,
  }) async {}
}

/// Opens a URL outside the app.
abstract interface class ExternalLinkService {
  Future<bool> open(Uri uri);
}

class UrlExternalLinkService implements ExternalLinkService {
  const UrlExternalLinkService();

  @override
  Future<bool> open(Uri uri) async {
    // Only ever hand http(s) to the OS. Anything else could be an intent or
    // file scheme we have not vetted.
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Light haptics, used only where state genuinely changes.
///
/// Not decorative: following a team and committing a filter are the only two
/// places this fires.
/// Opens the OS screens the app cannot change itself.
///
/// Android will not let an app re-request a permission the user denied, so the
/// only way out of a denial is the system settings page. Without this the app
/// can describe the problem but not offer a way to fix it.
abstract interface class SystemSettingsService {
  /// True when the settings screen was actually opened.
  Future<bool> openNotificationSettings();
}

class AndroidSystemSettingsService implements SystemSettingsService {
  const AndroidSystemSettingsService();

  @override
  Future<bool> openNotificationSettings() async {
    // An `intent:` URI rather than a new plugin dependency. The package name
    // comes from the running build, so a flavour or a rename cannot send the
    // user to some other app's settings.
    final info = await PackageInfo.fromPlatform();
    final uri = Uri.parse(
      'intent:#Intent;action=android.settings.APP_NOTIFICATION_SETTINGS;'
      'S.android.provider.extra.APP_PACKAGE=${info.packageName};end',
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Used where there is nothing to open — other platforms, and tests.
class UnsupportedSystemSettingsService implements SystemSettingsService {
  const UnsupportedSystemSettingsService();

  @override
  Future<bool> openNotificationSettings() async => false;
}

abstract interface class HapticsService {
  Future<void> selection();
  Future<void> confirm();
}

class PlatformHapticsService implements HapticsService {
  const PlatformHapticsService();

  @override
  Future<void> selection() async {
    try {
      await HapticFeedback.selectionClick();
    } on MissingPluginException {
      // Not available on this host.
    }
  }

  @override
  Future<void> confirm() async {
    try {
      await HapticFeedback.lightImpact();
    } on MissingPluginException {
      // Not available on this host.
    }
  }
}

class NoopHapticsService implements HapticsService {
  const NoopHapticsService();

  @override
  Future<void> selection() async {}

  @override
  Future<void> confirm() async {}
}

/// Bundle of platform services, resolved once at startup.
@immutable
class PlatformServices {
  const PlatformServices({
    required this.calendar,
    required this.maps,
    required this.sharing,
    required this.externalLinks,
    required this.haptics,
    required this.systemSettings,
  });

  final CalendarService calendar;
  final MapsService maps;
  final SharingService sharing;
  final ExternalLinkService externalLinks;
  final HapticsService haptics;
  final SystemSettingsService systemSettings;

  /// Real implementations for the running platform.
  factory PlatformServices.forCurrentPlatform() {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    return PlatformServices(
      // iOS lands here next: an EventKit-backed CalendarService, registered in
      // exactly this one place.
      calendar: isAndroid
          ? const AndroidCalendarService()
          : const UnsupportedCalendarService(),
      maps: const UrlMapsService(),
      sharing: const PlatformSharingService(),
      externalLinks: const UrlExternalLinkService(),
      haptics: const PlatformHapticsService(),
      systemSettings: isAndroid
          ? const AndroidSystemSettingsService()
          : const UnsupportedSystemSettingsService(),
    );
  }

  /// Inert implementations for widget tests and golden runs.
  factory PlatformServices.noop() => const PlatformServices(
    calendar: UnsupportedCalendarService(),
    maps: _NoopMapsService(),
    sharing: NoopSharingService(),
    externalLinks: _NoopLinkService(),
    haptics: NoopHapticsService(),
    systemSettings: UnsupportedSystemSettingsService(),
  );

  /// Swaps out one or more services. Used by tests that need to observe a
  /// single edge (e.g. a recording [SharingService]) without hand-assembling
  /// every other field.
  PlatformServices copyWith({
    CalendarService? calendar,
    MapsService? maps,
    SharingService? sharing,
    ExternalLinkService? externalLinks,
    HapticsService? haptics,
    SystemSettingsService? systemSettings,
  }) => PlatformServices(
    calendar: calendar ?? this.calendar,
    maps: maps ?? this.maps,
    sharing: sharing ?? this.sharing,
    externalLinks: externalLinks ?? this.externalLinks,
    haptics: haptics ?? this.haptics,
    systemSettings: systemSettings ?? this.systemSettings,
  );
}

class _NoopMapsService implements MapsService {
  const _NoopMapsService();

  @override
  Future<bool> openDirections({
    double? latitude,
    double? longitude,
    String? address,
    String? label,
  }) async => false;
}

class _NoopLinkService implements ExternalLinkService {
  const _NoopLinkService();

  @override
  Future<bool> open(Uri uri) async => false;
}
