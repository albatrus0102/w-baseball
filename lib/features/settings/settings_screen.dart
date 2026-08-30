import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/audience.dart';

/// Start-screen mode, region, spoiler policy, and beginner explanations.
///
/// Everything the onboarding asked can be changed here at any time, and none
/// of it locks a feature — mode only reorders the home screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final audience = ref.watch(audienceProvider);
    final controller = ref.read(audienceControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('시작 화면과 지역')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          WbSpace.screen,
          WbSpace.md,
          WbSpace.screen,
          WbSpace.xxl,
        ),
        children: <Widget>[
          Text('시작 화면', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.xs),
          Text(
            '홈 모듈 순서와 설명 깊이만 달라집니다. 기능은 잠기지 않습니다.',
            style: WbType.caption.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: WbSpace.md),
          WbCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                for (final mode in AudienceMode.values)
                  RadioListTile<AudienceMode>(
                    value: mode,
                    // ignore: deprecated_member_use
                    groupValue: audience.mode,
                    // ignore: deprecated_member_use
                    onChanged: (value) {
                      if (value != null) controller.setMode(value);
                    },
                    title: Text(mode.labelKo, style: WbType.body),
                  ),
              ],
            ),
          ),

          const SizedBox(height: WbSpace.section),
          Text('지역', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.xs),
          Text(
            // Restated here because it is the point: the app is fully usable
            // without granting location.
            '근처 경기를 찾는 데 사용합니다. 위치 권한 없이 지역만 선택해도 됩니다.',
            style: WbType.caption.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: WbSpace.md),
          Wrap(
            spacing: WbSpace.sm,
            runSpacing: WbSpace.sm,
            children: <Widget>[
              WbFilterChip(
                label: '선택 안 함',
                selected: !audience.hasRegion,
                onTap: () => controller.setRegion(null, null),
              ),
              for (final region in KoreanRegion.all)
                WbFilterChip(
                  label: region.name,
                  selected: audience.regionCode == region.code,
                  onTap: () => controller.setRegion(region.code, region.name),
                ),
            ],
          ),

          const SizedBox(height: WbSpace.section),
          Text('콘텐츠', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.md),
          WbCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  value: audience.spoilerPolicy == SpoilerPolicy.hide,
                  onChanged: (value) => controller.setSpoilerPolicy(
                    value ? SpoilerPolicy.hide : SpoilerPolicy.reveal,
                  ),
                  title: Text('결과 가리기', style: WbType.body),
                  subtitle: Text(
                    '카드, 상세 화면, 알림에 모두 적용됩니다.',
                    style: WbType.micro.copyWith(color: c.inkMuted),
                  ),
                ),
                Divider(height: 1, color: c.divider),
                SwitchListTile(
                  value: audience.showBeginnerExplanations,
                  onChanged: controller.setBeginnerExplanations,
                  title: Text('초보 설명 보기', style: WbType.body),
                  subtitle: Text(
                    '기록 용어와 배경 설명을 화면 안에 함께 보여줍니다.',
                    style: WbType.micro.copyWith(color: c.inkMuted),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: WbSpace.section),
          Text('보기 밀도', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.xs),
          Text(
            // Says plainly what density does *not* do, because a setting that
            // looks like it might hide information stops people from trying it.
            '글자 크기와 여백만 달라집니다. 어떤 정보도 사라지지 않습니다.',
            style: WbType.caption.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: WbSpace.md),
          WbCard(
            padding: EdgeInsets.zero,
            child: RadioGroup<WbDensity>(
              groupValue: audience.density,
              onChanged: (value) => controller.setDensity(value),
              child: Column(
                children: <Widget>[
                  for (final option in WbDensity.values)
                    RadioListTile<WbDensity>(
                      value: option,
                      title: Text(option.labelKo, style: WbType.body),
                      subtitle: Text(
                        option.descriptionKo,
                        style: WbType.micro.copyWith(color: c.inkMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (audience.densityOverride != null) ...<Widget>[
            const SizedBox(height: WbSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => controller.setDensity(null),
                child: Text(
                  '모드 기본값으로 되돌리기 '
                  '(${audience.mode.shortLabelKo} → '
                  '${audience.mode.defaultDensity.labelKo})',
                ),
              ),
            ),
          ],

          const SizedBox(height: WbSpace.section),
          Text('근처 경기 반경', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.md),
          WbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${audience.searchRadiusKm}km 이내',
                  style: WbType.tabular.copyWith(color: c.ink),
                ),
                Slider(
                  value: audience.searchRadiusKm.toDouble(),
                  min: 10,
                  max: 150,
                  divisions: 14,
                  label: '${audience.searchRadiusKm}km',
                  onChanged: (value) =>
                      controller.setSearchRadius(value.round()),
                ),
                Text(
                  '거리 계산은 기기 안에서만 이루어지며, 위치 정보는 저장하거나 전송하지 않습니다.',
                  style: WbType.micro.copyWith(color: c.inkMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
