import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/tokens.dart';
import '../core/design_system/theme.dart';
import 'providers.dart';
import 'router.dart';

/// The application root.
class WbApp extends ConsumerWidget {
  const WbApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '여자야구',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: WbTheme.light(),
      darkTheme: WbTheme.dark(),
      themeMode: ThemeMode.system,
      // Korean first. English is listed so system widgets (date pickers,
      // selection handles) still resolve on an English-locale device, but no
      // machine-translated app strings are shipped.
      locale: const Locale('ko', 'KR'),
      supportedLocales: const <Locale>[Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Android's accessibility font setting reaches 2.0, and someone who
        // needs it needs it — so the ceiling matches the platform rather than
        // capping what the OS offers. Checked at 1.3 / 1.4 / 1.7 / 2.0 on a
        // 360dp screen, scrolled to the end before measuring, in
        // `text_scale_probe_test.dart` (currently: home, games, my-baseball,
        // game detail — every screen that test can mount, not necessarily
        // every screen in the app). The previous 1.4 cap was hiding real
        // overflows rather than preventing them.
        //
        // The floor stays: below ~0.85 the tabular score figures stop being
        // legible, and nothing is gained by honouring it.
        final media = MediaQuery.of(context);
        final clamped = media.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 2.0,
        );
        return MediaQuery(
          data: media.copyWith(textScaler: clamped),
          child: WbDensityHost(
            child: WbFreshnessHost(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}

/// Publishes the user's information density to the whole tree.
///
/// Lives above the router so a full-screen route (검색, 상세) gets the same
/// density as the tab it was opened from, and so a density change repaints
/// every screen at once instead of only the visible one.
///
/// Exposed rather than inlined because widget tests build their own
/// `MaterialApp` and must be able to render at a chosen density.
class WbDensityHost extends ConsumerWidget {
  const WbDensityHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WbDensityScope(density: ref.watch(densityProvider), child: child);
  }
}

/// Publishes whether a freshness verdict may currently be rendered, and how
/// stale is too stale, to the whole tree.
///
/// Same placement as [WbDensityHost] and the same reason: computing
/// `freshnessThresholdProvider` once here means every `WbSourceLine` agrees,
/// instead of each of its call sites asking Riverpod — and risking a
/// forgotten one silently keeping the old always-12-hours behaviour.
class WbFreshnessHost extends ConsumerWidget {
  const WbFreshnessHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WbFreshnessScope(
      staleAfter: ref.watch(freshnessThresholdProvider),
      child: child,
    );
  }
}
