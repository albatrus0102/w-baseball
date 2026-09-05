import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/utils/kst.dart';
import '../../data/models/game_log.dart';
import '../../data/repositories/game_log_import_repository.dart';

/// 출전 일지 가져오기 — the two permanent entry points named in the feature
/// brief: ① the "⋮" menu on 내 기록 (see `_GameLogMenuButton` in
/// `game_log_widgets.dart`) offers 가져오기 itself and 가져온 기록 관리; ②
/// the result screen's own "되돌리기" button right after a fresh import (see
/// [_GameLogImportResultScreen]).
///
/// Opens the OS picker, parses whatever comes back, and — only once the
/// player confirms the preview screen — writes it as one all-or-nothing
/// batch. See `GameLogImportRepository`'s doc for the dedupe rule, the
/// commit transaction, and the undo contract.
Future<void> importGameLog(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repo = ref.read(gameLogImportRepositoryProvider);
  final pick = await repo.pickAndPreview();
  if (!context.mounted) return;

  switch (pick) {
    case GameLogImportCancelled():
      return; // The user backed out of the picker. Nothing to say.
    case GameLogImportFormatError(:final message):
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    case GameLogImportReady(:final preview):
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _GameLogImportPreviewScreen(preview: preview),
        ),
      );
  }
}

/// "가져오기 미리보기" — shown before anything is written. See the feature
/// brief: this is the one defence against importing someone else's file, so
/// it always shows what the file actually contains, never just a count.
class _GameLogImportPreviewScreen extends ConsumerStatefulWidget {
  const _GameLogImportPreviewScreen({required this.preview});

  final GameLogImportPreview preview;

  @override
  ConsumerState<_GameLogImportPreviewScreen> createState() =>
      _GameLogImportPreviewScreenState();
}

class _GameLogImportPreviewScreenState
    extends ConsumerState<_GameLogImportPreviewScreen> {
  bool _committing = false;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final preview = widget.preview;
    final first = preview.firstByPlayedAt;
    final last = preview.lastByPlayedAt;
    final sampleNote = preview.sampleNote;

    return Scaffold(
      appBar: AppBar(title: const Text('가져오기 미리보기')),
      body: ListView(
        padding: const EdgeInsets.all(WbSpace.screen),
        children: <Widget>[
          if (preview.fileLabel != null) ...<Widget>[
            Text(
              preview.fileLabel!,
              style: WbType.captionStrong.copyWith(color: c.ink),
            ),
            const SizedBox(height: WbSpace.xxs),
          ],
          Text(
            preview.fileExportedAt == null
                ? '기록 ${preview.entries.length}건'
                : '${KoDate.fullDate(preview.fileExportedAt!)}에 내보낸 파일 · '
                      '기록 ${preview.entries.length}건',
            style: WbType.body.copyWith(color: c.inkMuted),
          ),
          if (first != null && last != null) ...<Widget>[
            const SizedBox(height: WbSpace.lg),
            Text(
              '기간: ${KoDate.fullDate(first.playedAt)} ~ '
              '${KoDate.fullDate(last.playedAt)}',
              style: WbType.body.copyWith(color: c.ink),
            ),
            const SizedBox(height: WbSpace.xs),
            Text(
              '첫 기록: ${_lineKo(first)}',
              style: WbType.body.copyWith(color: c.ink),
            ),
            Text(
              '마지막 기록: ${_lineKo(last)}',
              style: WbType.body.copyWith(color: c.ink),
            ),
          ],
          if (sampleNote != null) ...<Widget>[
            const SizedBox(height: WbSpace.xs),
            Text(
              '메모 예: "$sampleNote"',
              style: WbType.caption.copyWith(color: c.inkMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: WbSpace.lg),
          Text(
            '이 파일이 내 기록이 맞는지 확인해 주세요.\n'
            '다른 사람의 파일을 가져오면 내 일지와 섞입니다.\n'
            '가져온 뒤에도 이 묶음만 한 번에 되돌릴 수 있어요.',
            style: WbType.caption.copyWith(color: c.inkMuted, height: 1.6),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(WbSpace.screen),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _committing
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: WbSpace.md),
              Expanded(
                child: FilledButton(
                  onPressed: preview.isEmpty || _committing ? null : _commit,
                  child: Text('${preview.entries.length}건 가져오기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "4월 12일 · 상대 OO클럽 · 승" — falls back to the same "상대 미기록"
  /// wording `_GameLogEntryTile` already uses for a blank opponent.
  String _lineKo(GameLogEntry entry) {
    final opponent = entry.opponentLabel;
    final opponentLabel = (opponent == null || opponent.isEmpty)
        ? '상대 미기록'
        : opponent;
    return '${KoDate.monthDay(entry.playedAt)} · 상대 $opponentLabel · '
        '${entry.result.labelKo}';
  }

  Future<void> _commit() async {
    setState(() => _committing = true);
    final repo = ref.read(gameLogImportRepositoryProvider);
    final result = await repo.commit(widget.preview);
    await ref.read(analyticsProvider).log(AnalyticsEvent.gameLogImported);
    if (!mounted) return;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => _GameLogImportResultScreen(result: result),
      ),
    );
  }
}

/// "가져오기 완료" — the entry point ① of the two permanent 되돌리기
/// affordances the feature brief names (the other is "가져온 기록 관리",
/// reachable forever, not just right after an import).
class _GameLogImportResultScreen extends ConsumerStatefulWidget {
  const _GameLogImportResultScreen({required this.result});

  final GameLogImportCommitResult result;

  @override
  ConsumerState<_GameLogImportResultScreen> createState() =>
      _GameLogImportResultScreenState();
}

class _GameLogImportResultScreenState
    extends ConsumerState<_GameLogImportResultScreen> {
  bool _undoing = false;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final result = widget.result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('가져오기 완료'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(WbSpace.screen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${result.insertedCount}건을 추가했어요.',
              style: WbType.title.copyWith(color: c.ink),
            ),
            if (result.duplicateCount > 0) ...<Widget>[
              const SizedBox(height: WbSpace.sm),
              Text(
                '이미 있던 ${result.duplicateCount}건은 건너뛰었어요.',
                style: WbType.body.copyWith(color: c.inkMuted),
              ),
            ],
            if (result.invalidCount > 0) ...<Widget>[
              const SizedBox(height: WbSpace.sm),
              Text(
                '${result.invalidCount}건은 읽을 수 없어 건너뛰었어요.',
                style: WbType.body.copyWith(color: c.inkMuted),
              ),
            ],
            const SizedBox(height: WbSpace.lg),
            Text(
              '잘못 가져왔다면 지금이 아니어도\n언제든 한 번에 되돌릴 수 있어요.',
              style: WbType.caption.copyWith(color: c.inkMuted, height: 1.6),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(WbSpace.screen),
          child: Row(
            children: <Widget>[
              if (result.insertedCount > 0) ...<Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _undoing ? null : _undo,
                    child: Text('방금 가져온 ${result.insertedCount}건 되돌리기'),
                  ),
                ),
                const SizedBox(width: WbSpace.md),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _undoing
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _undo() async {
    setState(() => _undoing = true);
    final repo = ref.read(gameLogImportRepositoryProvider);
    await repo.undo(widget.result.batchId);
    await ref.read(analyticsProvider).log(AnalyticsEvent.gameLogImportUndone);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('되돌렸어요.')));
    Navigator.of(context).pop();
  }
}

/// "가져온 기록 관리" — entry point ② of the two permanent 되돌리기
/// affordances, reachable from 내 기록's "⋮" menu forever (no expiry — see
/// `GameLogImportRepository`'s doc).
class GameLogImportManageScreen extends ConsumerWidget {
  const GameLogImportManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(gameLogImportBatchesProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('가져온 기록 관리')),
      body: batches == null
          ? const SizedBox.shrink()
          : batches.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(WbSpace.screen),
              child: WbEmptyState(
                compact: true,
                icon: Icons.inbox_outlined,
                title: '가져온 기록이 없습니다',
                message: '기기를 바꿨거나 내보내둔 파일이 있다면 여기서 가져올 수 있어요.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(WbSpace.screen),
              children: <Widget>[
                for (final batch in batches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WbSpace.sm),
                    child: _ImportBatchCard(batch: batch),
                  ),
              ],
            ),
    );
  }
}

class _ImportBatchCard extends ConsumerStatefulWidget {
  const _ImportBatchCard({required this.batch});

  final GameLogImportBatch batch;

  @override
  ConsumerState<_ImportBatchCard> createState() => _ImportBatchCardState();
}

class _ImportBatchCardState extends ConsumerState<_ImportBatchCard> {
  bool _undoing = false;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final batch = widget.batch;

    final detailParts = <String>[
      '${batch.insertedCount}건 추가',
      if (batch.duplicateCount > 0) '${batch.duplicateCount}건 중복',
      if (batch.invalidCount > 0) '${batch.invalidCount}건 읽기 실패',
    ];

    return WbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            batch.fileLabel ?? '가져온 파일',
            style: WbType.captionStrong.copyWith(color: c.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: WbSpace.xxs),
          Text(
            '${KoDate.fullDate(batch.importedAt)}에 가져옴 · '
            '${detailParts.join(' · ')}',
            style: WbType.caption.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: WbSpace.sm),
          Align(
            alignment: Alignment.centerRight,
            child: batch.isUndone
                ? const WbBadge(
                    label: '되돌림',
                    tone: WbBadgeTone.muted,
                    dense: true,
                  )
                : batch.insertedCount == 0
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: _undoing ? null : _confirmUndo,
                    child: const Text('되돌리기'),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUndo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 가져오기를 되돌릴까요?'),
        content: Text('이 묶음으로 추가된 ${widget.batch.insertedCount}건이 삭제됩니다.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('되돌리기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _undoing = true);
    final repo = ref.read(gameLogImportRepositoryProvider);
    await repo.undo(widget.batch.id);
    await ref.read(analyticsProvider).log(AnalyticsEvent.gameLogImportUndone);
    if (!mounted) return;
    setState(() => _undoing = false);
  }
}

/// "⋮" on 내 기록 — 가져오기 and 가져온 기록 관리. See `game_log_widgets.dart`'s
/// `_GameLogSectionHeader`, the only caller.
class GameLogMenuButton extends ConsumerWidget {
  const GameLogMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return PopupMenuButton<String>(
      tooltip: '더보기',
      icon: Icon(Icons.more_vert_rounded, color: c.inkMuted),
      onSelected: (value) {
        switch (value) {
          case 'import':
            importGameLog(context, ref);
          case 'manage':
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const GameLogImportManageScreen(),
              ),
            );
        }
      },
      itemBuilder: (context) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'import', child: Text('가져오기')),
        PopupMenuItem<String>(value: 'manage', child: Text('가져온 기록 관리')),
      ],
    );
  }
}
