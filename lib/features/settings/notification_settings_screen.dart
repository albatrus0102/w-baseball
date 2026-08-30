import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../data/models/reminder_status.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/audience.dart';

/// Notification categories and follows, on one screen.
///
/// Two decisions drive the layout:
///  * every category has its own switch — the loudest complaint about the
///    incumbent Korean baseball app is all-or-nothing notifications,
///  * follows live here too, so "why am I getting this?" and "stop it" are the
///    same gesture in the same place.
///
/// Permission is requested the first time a category is switched on, never at
/// launch, and never again after a refusal.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final prefsAsync = ref.watch(notificationPreferenceProvider);
    final follows = ref.watch(followRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('알림과 팔로우')),
      body: prefsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(WbSpace.screen),
          child: WbSkeleton(height: 200, borderRadius: WbRadius.cardAll),
        ),
        error: (_, _) => WbEmptyState(
          icon: Icons.error_outline_rounded,
          tone: WbBadgeTone.danger,
          title: '알림 설정을 불러오지 못했습니다',
        ),
        data: (prefs) => ListView(
          padding: const EdgeInsets.fromLTRB(
            WbSpace.screen,
            WbSpace.md,
            WbSpace.screen,
            WbSpace.xxl,
          ),
          children: <Widget>[
            const _ScheduledCount(),
            const SizedBox(height: WbSpace.md),
            Container(
              padding: const EdgeInsets.all(WbSpace.md),
              decoration: BoxDecoration(
                color: c.brandSoft,
                borderRadius: WbRadius.chipAll,
              ),
              child: Text(
                '첫 버전은 기기에 저장된 일정으로 알림을 예약합니다. '
                '앱을 열지 않아도 동작하지만, 일정이 바뀐 사실은 앱을 열어 갱신할 때 반영됩니다.',
                style: WbType.caption.copyWith(color: c.ink, height: 1.6),
              ),
            ),

            const SizedBox(height: WbSpace.xl),
            Text('경기와 일정', style: WbType.section.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.md),
            _CategoryGroup(
              prefs: prefs,
              categories: NotificationCategory.values
                  .where((c) => c.isPlayerOriented)
                  .toList(),
            ),

            const SizedBox(height: WbSpace.section),
            Text('콘텐츠와 소식', style: WbType.section.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.md),
            _CategoryGroup(
              prefs: prefs,
              categories: NotificationCategory.values
                  .where((c) => !c.isPlayerOriented)
                  .toList(),
            ),

            const SizedBox(height: WbSpace.section),
            Text('조용한 시간', style: WbType.section.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.xs),
            Text(
              '이 시간에 예정된 알림은 사라지지 않고, 시간이 끝난 뒤에 전달됩니다.',
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: WbSpace.md),
            _QuietHours(prefs: prefs),

            const SizedBox(height: WbSpace.section),
            Text('스포일러', style: WbType.section.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.md),
            WbCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: prefs.allowSpoilersInNotifications,
                onChanged: (value) => ref
                    .read(preferencesProvider)
                    .saveNotifications(
                      prefs.copyWith(allowSpoilersInNotifications: value),
                    ),
                title: Text('알림에 결과 포함', style: WbType.body),
                subtitle: Text(
                  '꺼두면 회차 요약 알림에 결과를 넣지 않습니다.',
                  style: WbType.micro.copyWith(color: c.inkMuted),
                ),
              ),
            ),

            const SizedBox(height: WbSpace.section),
            Text('팔로우 중', style: WbType.section.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.xs),
            Text(
              '알림을 받는 이유입니다. 여기서 바로 해제할 수 있습니다.',
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: WbSpace.md),
            StreamBuilder<List<LocalFollow>>(
              stream: follows.watchFollows(),
              builder: (context, snapshot) {
                final list = snapshot.data ?? const <LocalFollow>[];
                if (list.isEmpty) {
                  return WbEmptyState(
                    compact: true,
                    icon: Icons.star_border_rounded,
                    title: '팔로우 중인 항목이 없습니다',
                    message: '팀이나 프로그램을 팔로우하면 관련 알림을 받을 수 있습니다.',
                    primaryLabel: '팀 찾기',
                    onPrimary: () => context.push(WbRoutes.teams),
                  );
                }
                return WbCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      for (var i = 0; i < list.length; i++) ...<Widget>[
                        ListTile(
                          leading: Icon(
                            switch (list[i].kind) {
                              FollowKind.team => Icons.groups_outlined,
                              FollowKind.competition =>
                                Icons.emoji_events_outlined,
                              FollowKind.person => Icons.person_outline_rounded,
                              FollowKind.program => Icons.tv_rounded,
                              FollowKind.topic => Icons.tag_rounded,
                            },
                            color: c.brand,
                            size: 20,
                          ),
                          title: Text(
                            list[i].label ?? list[i].entityId,
                            style: WbType.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            list[i].kind.labelKo,
                            style: WbType.micro.copyWith(color: c.inkMuted),
                          ),
                          trailing: TextButton(
                            onPressed: () => follows.unfollow(
                              list[i].kind,
                              list[i].entityId,
                            ),
                            child: const Text('해제'),
                          ),
                        ),
                        if (i < list.length - 1)
                          Divider(height: 1, color: c.divider),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryGroup extends ConsumerWidget {
  const _CategoryGroup({required this.prefs, required this.categories});

  final NotificationPreference prefs;
  final List<NotificationCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return WbCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (var i = 0; i < categories.length; i++) ...<Widget>[
            SwitchListTile(
              value: prefs.isEnabled(categories[i]),
              onChanged: (value) => _toggle(ref, categories[i], value),
              title: Text(categories[i].labelKo, style: WbType.body),
              subtitle: Text(
                categories[i].descriptionKo,
                style: WbType.micro.copyWith(color: c.inkMuted),
              ),
            ),
            if (i < categories.length - 1) Divider(height: 1, color: c.divider),
          ],
        ],
      ),
    );
  }

  Future<void> _toggle(
    WidgetRef ref,
    NotificationCategory category,
    bool value,
  ) async {
    final store = ref.read(preferencesProvider);
    var next = prefs.enabled.toSet();
    value ? next.add(category) : next.remove(category);

    var updated = prefs.copyWith(enabled: next);

    // Ask for the OS permission the first time a category is switched on,
    // where the value is obvious. Never at launch, never twice.
    if (value && !prefs.permissionRequested) {
      final service = ref.read(notificationServiceProvider);
      await service.initialize();
      await service.requestPermission();
      updated = updated.copyWith(permissionRequested: true);
    }

    await store.saveNotifications(updated);
    if (value) {
      await ref
          .read(analyticsProvider)
          .log(
            AnalyticsEvent.notificationCategoryEnabled,
            properties: <String, Object?>{'category': category.wireValue},
          );
    }
  }
}

class _QuietHours extends ConsumerWidget {
  const _QuietHours({required this.prefs});

  final NotificationPreference prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    String label(int? minute) {
      if (minute == null) return '설정 안 함';
      final h = (minute ~/ 60).toString().padLeft(2, '0');
      final m = (minute % 60).toString().padLeft(2, '0');
      return '$h:$m';
    }

    return WbCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          SwitchListTile(
            value: prefs.hasQuietHours,
            onChanged: (value) => ref
                .read(preferencesProvider)
                .saveNotifications(
                  value
                      ? prefs.copyWith(
                          quietHoursStartMinute: 22 * 60,
                          quietHoursEndMinute: 8 * 60,
                        )
                      : prefs.copyWith(clearQuietHours: true),
                ),
            title: Text('조용한 시간 사용', style: WbType.body),
          ),
          if (prefs.hasQuietHours) ...<Widget>[
            Divider(height: 1, color: c.divider),
            ListTile(
              title: Text('시작', style: WbType.body),
              trailing: Text(
                label(prefs.quietHoursStartMinute),
                style: WbType.tabular.copyWith(color: c.ink),
              ),
              onTap: () => _pick(context, ref, isStart: true),
            ),
            Divider(height: 1, color: c.divider),
            ListTile(
              title: Text('종료', style: WbType.body),
              trailing: Text(
                label(prefs.quietHoursEndMinute),
                style: WbType.tabular.copyWith(color: c.ink),
              ),
              onTap: () => _pick(context, ref, isStart: false),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required bool isStart,
  }) async {
    final current = isStart
        ? prefs.quietHoursStartMinute
        : prefs.quietHoursEndMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (current ?? (isStart ? 1320 : 480)) ~/ 60,
        minute: (current ?? 0) % 60,
      ),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await ref
        .read(preferencesProvider)
        .saveNotifications(
          isStart
              ? prefs.copyWith(quietHoursStartMinute: minutes)
              : prefs.copyWith(quietHoursEndMinute: minutes),
        );
  }
}

/// How many alerts are actually registered right now.
///
/// Settings toggles describe intent; this line reports the result. Without it
/// there is no way for a user — or a developer — to tell "no alerts because I
/// follow nothing" apart from "no alerts because scheduling is broken".
class _ScheduledCount extends ConsumerWidget {
  const _ScheduledCount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final status = ref.watch(reminderStatusProvider);

    final text = switch (status) {
      AsyncData(:final value) => value.summaryKo,
      AsyncError() => '알림 예약 상태를 확인하지 못했습니다.',
      _ => '알림 예약 상태를 확인하는 중입니다.',
    };
    final blocker = status.value?.blocker;
    // Only the OS denial gets a button here: the user is already on the app's
    // own notification screen, so pointing at it again would be a loop.
    final denied = blocker == ReminderBlocker.permissionDenied;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              denied ? Icons.notifications_off_rounded : Icons.schedule_rounded,
              size: 16,
              color: denied ? c.action : c.inkMuted,
            ),
            const SizedBox(width: WbSpace.sm),
            Expanded(
              child: Text(
                text,
                style: WbType.caption.copyWith(
                  color: denied ? c.ink : c.inkMuted,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        if (denied)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref
                  .read(platformServicesProvider)
                  .systemSettings
                  .openNotificationSettings(),
              child: Text(ReminderBlocker.permissionDenied.actionLabelKo!),
            ),
          ),
      ],
    );
  }
}
