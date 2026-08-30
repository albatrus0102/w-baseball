import 'package:drift/drift.dart';

import '../../core/config/app_config.dart';
import '../../core/database/database.dart';
import '../dto/dtos.dart';
import '../mappers/dto_mappers.dart';
import '../models/domain.dart' show GameStatus;
import '../sources/sports_data_source.dart';
import '../sources/static_manifest_data_source.dart';
import 'sync_contracts.dart';

/// Applies data from any [SportsDataSource] into the local database.
///
/// Guarantees the rest of the app relies on:
///  * **Atomicity** — every entity type is applied inside one transaction. A
///    failure part-way leaves the previous good data completely intact.
///  * **Idempotency** — re-receiving the same page changes nothing. Upserts key
///    on the canonical id, so duplicates collapse instead of accumulating.
///  * **Isolation** — a source that fails is recorded and skipped; the others
///    still apply. One broken feed never empties the app.
///  * **No silent deletion** — records absent from a *snapshot* are tombstoned,
///    never hard-deleted. Records absent from a *delta* mean "unchanged".
///  * **Cache preservation** — an unsupported schema version stops the refresh
///    before writing anything.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.config,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final AppConfig config;
  final DateTime Function() _clock;

  int _idCounter = 0;

  /// Refreshes every enabled source, isolating failures per source.
  Future<SyncReport> refreshAll(
    List<SportsDataSource> sources, {
    GameSyncScope? scope,
    bool incremental = true,
  }) async {
    final results = <SyncResult>[];
    final effectiveScope = scope ?? GameSyncScope.aroundNow(_clock().toUtc());

    for (final source in sources) {
      if (!source.isEnabled) continue;
      try {
        results.add(
          await refreshSource(
            source,
            scope: effectiveScope,
            incremental: incremental,
          ),
        );
      } on Object catch (error) {
        // Defence in depth: refreshSource already converts failures into a
        // SyncResult, so reaching here means something unexpected. It still
        // must not stop the remaining sources.
        final now = _clock().toUtc();
        results.add(
          SyncResult.failed(
            sourceName: source.sourceName,
            kind: SyncFailureKind.unknown,
            startedAt: now,
            finishedAt: now,
            message: error.toString(),
          ),
        );
      }
    }

    return SyncReport(results: results, finishedAt: _clock().toUtc());
  }

  /// Refreshes a single source across all entity types it supports.
  Future<SyncResult> refreshSource(
    SportsDataSource source, {
    required GameSyncScope scope,
    bool incremental = true,
  }) async {
    final startedAt = _clock().toUtc();
    final runId = _nextId('run');
    final issues = <SyncIssue>[];

    var inserted = 0;
    var updated = 0;
    var tombstoned = 0;
    var unchanged = 0;
    var pages = 0;
    String? dataVersion;

    await db
        .into(db.syncRuns)
        .insert(
          SyncRunsCompanion.insert(
            id: runId,
            sourceName: source.sourceName,
            startedAt: startedAt,
          ),
          mode: InsertMode.insertOrReplace,
        );

    try {
      final supported = source.supportedEntities;

      // Reference data first: teams and venues must exist before games can be
      // meaningfully displayed, and competitions before standings.
      if (supported.contains(SyncEntityType.organization)) {
        final r = await _syncPaged<OrganizationDto>(
          source: source,
          entity: SyncEntityType.organization,
          incremental: incremental,
          fetch: (req) => source.fetchOrganizations(req),
          apply: _applyOrganizations,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        tombstoned += r.tombstoned;
        unchanged += r.unchanged;
        dataVersion ??= r.dataVersion;
      }

      if (supported.contains(SyncEntityType.venue)) {
        final r = await _syncPaged<VenueDto>(
          source: source,
          entity: SyncEntityType.venue,
          incremental: incremental,
          fetch: (req) => source.fetchVenues(req),
          apply: _applyVenues,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        tombstoned += r.tombstoned;
        unchanged += r.unchanged;
        dataVersion ??= r.dataVersion;
      }

      if (supported.contains(SyncEntityType.team)) {
        final r = await _syncPaged<TeamDto>(
          source: source,
          entity: SyncEntityType.team,
          incremental: incremental,
          fetch: (req) => source.fetchTeams(req),
          apply: _applyTeams,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        tombstoned += r.tombstoned;
        unchanged += r.unchanged;
        dataVersion ??= r.dataVersion;
      }

      if (supported.contains(SyncEntityType.competition)) {
        final r = await _syncPaged<CompetitionDto>(
          source: source,
          entity: SyncEntityType.competition,
          incremental: incremental,
          fetch: (req) => source.fetchCompetitions(req),
          apply: _applyCompetitions,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        tombstoned += r.tombstoned;
        unchanged += r.unchanged;
        dataVersion ??= r.dataVersion;
      }

      if (supported.contains(SyncEntityType.person)) {
        final r = await _syncPaged<PersonDto>(
          source: source,
          entity: SyncEntityType.person,
          incremental: incremental,
          fetch: (req) => source.fetchPeople(req),
          apply: _applyPeople,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        unchanged += r.unchanged;
      }

      if (supported.contains(SyncEntityType.rosterEntry)) {
        final r = await _syncPaged<RosterEntryDto>(
          source: source,
          entity: SyncEntityType.rosterEntry,
          incremental: incremental,
          fetch: (req) => source.fetchRoster(req),
          apply: _applyRoster,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        unchanged += r.unchanged;
      }

      // Games are requested per month partition so we never ask for
      // "everything" and never re-download a whole season to see one change.
      if (supported.contains(SyncEntityType.game)) {
        final months = scope.months.isEmpty
            ? <String?>[null]
            : scope.months.cast<String?>();
        for (final month in months) {
          final r = await _syncPaged<GameDto>(
            source: source,
            entity: SyncEntityType.game,
            incremental: incremental && !scope.fullRefresh,
            scopeKey: month,
            fetch: (req) => source.fetchGames(
              GameSyncRequest(
                month: month,
                cursor: req.cursor,
                pageNumber: req.pageNumber,
                pageSize: req.pageSize,
                updatedSince: req.updatedSince,
                validators: req.validators,
                scopeKey: month,
              ),
            ),
            apply: _applyGames,
          );
          _accumulate(r, issues, () => pages += r.pages);
          inserted += r.inserted;
          updated += r.updated;
          tombstoned += r.tombstoned;
          unchanged += r.unchanged;
          dataVersion ??= r.dataVersion;
        }
      }

      if (supported.contains(SyncEntityType.standing)) {
        final r = await _syncPaged<StandingDto>(
          source: source,
          entity: SyncEntityType.standing,
          incremental: incremental,
          fetch: (req) => source.fetchStandings(req),
          apply: _applyStandings,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        unchanged += r.unchanged;
      }

      if (supported.contains(SyncEntityType.article)) {
        final r = await _syncPaged<ArticleDto>(
          source: source,
          entity: SyncEntityType.article,
          incremental: incremental,
          fetch: (req) => source.fetchArticles(req),
          apply: _applyArticles,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        unchanged += r.unchanged;
      }

      if (supported.contains(SyncEntityType.video)) {
        final r = await _syncPaged<VideoDto>(
          source: source,
          entity: SyncEntityType.video,
          incremental: incremental,
          fetch: (req) => source.fetchVideos(req),
          apply: _applyVideos,
        );
        _accumulate(r, issues, () => pages += r.pages);
        inserted += r.inserted;
        updated += r.updated;
        unchanged += r.unchanged;
      }

      // Cache validators are committed only now, after every transaction has
      // succeeded. Committing earlier would let a crash convince the next
      // launch that a file had been applied when it had not.
      if (source is StaticManifestDataSource) {
        await source.commitApplied();
      }

      final finishedAt = _clock().toUtc();
      final result = SyncResult(
        sourceName: source.sourceName,
        startedAt: startedAt,
        finishedAt: finishedAt,
        inserted: inserted,
        updated: updated,
        tombstoned: tombstoned,
        unchanged: unchanged,
        pagesFetched: pages,
        issues: issues,
        dataVersion: dataVersion,
        skippedBecauseNotModified:
            pages == 0 && inserted == 0 && updated == 0 && unchanged > 0,
      );
      await _finishRun(runId, result);
      return result;
    } on SyncException catch (e) {
      if (source is StaticManifestDataSource) source.discardPending();
      final finishedAt = _clock().toUtc();
      final result = SyncResult.failed(
        sourceName: source.sourceName,
        kind: e.kind,
        startedAt: startedAt,
        finishedAt: finishedAt,
        message: e.message ?? e.kind.messageKo,
        issues: issues,
      );
      await _finishRun(runId, result);
      return result;
    } on Object catch (e) {
      if (source is StaticManifestDataSource) source.discardPending();
      final finishedAt = _clock().toUtc();
      final result = SyncResult.failed(
        sourceName: source.sourceName,
        kind: SyncFailureKind.unknown,
        startedAt: startedAt,
        finishedAt: finishedAt,
        message: e.toString(),
        issues: issues,
      );
      await _finishRun(runId, result);
      return result;
    }
  }

  void _accumulate(
    _EntityOutcome outcome,
    List<SyncIssue> issues,
    void Function() addPages,
  ) {
    issues.addAll(outcome.issues);
    addPages();
  }

  /// Walks every page of one entity type and applies each inside a
  /// transaction.
  ///
  /// Pagination continues while `hasMore` is true and a cursor (or page
  /// number) keeps advancing; a source that returns the same cursor twice is
  /// stopped rather than looped forever.
  Future<_EntityOutcome> _syncPaged<T>({
    required SportsDataSource source,
    required SyncEntityType entity,
    required bool incremental,
    required Future<SyncPage<T>> Function(SyncRequest request) fetch,
    required Future<_ApplyCounts> Function(SyncPage<T> page) apply,
    String? scopeKey,
  }) async {
    final watermarkKey = _watermarkKey(source.sourceName, entity, scopeKey);
    final updatedSince = incremental
        ? await _readWatermark(watermarkKey)
        : null;

    var request = SyncRequest(
      pageNumber: 1,
      pageSize: config.futureApi.pageSize,
      updatedSince: updatedSince,
      scopeKey: scopeKey,
    );

    final issues = <SyncIssue>[];
    var inserted = 0;
    var updated = 0;
    var tombstoned = 0;
    var unchanged = 0;
    var pages = 0;
    String? dataVersion;
    DateTime? newestSeen;
    final seenCursors = <String>{};

    while (true) {
      final page = await fetch(request);
      issues.addAll(page.issues);
      dataVersion ??= page.dataVersion;

      if (page.notModified) {
        unchanged++;
        break;
      }

      pages++;

      final counts = await apply(page);
      inserted += counts.inserted;
      updated += counts.updated;
      tombstoned += counts.tombstoned;
      if (counts.newestTimestamp != null) {
        if (newestSeen == null || counts.newestTimestamp!.isAfter(newestSeen)) {
          newestSeen = counts.newestTimestamp;
        }
      }

      if (!page.hasMore) break;

      final next = page.nextCursor;
      if (next != null) {
        // Guard against a source that keeps handing back the same cursor.
        if (!seenCursors.add(next.value)) break;
        request = request.nextPage(next);
      } else if (request.pageNumber != null) {
        request = request.nextPage(null);
      } else {
        break;
      }

      // Hard ceiling so a misbehaving source cannot spin indefinitely.
      if (pages >= 200) {
        issues.add(
          SyncIssue(
            severity: SyncIssueSeverity.warning,
            sourceName: source.sourceName,
            entityType: entity.storageKey,
            message: '페이지 수 상한(200)에 도달해 동기화를 중단했습니다.',
          ),
        );
        break;
      }
    }

    if (newestSeen != null) {
      await _writeWatermark(watermarkKey, newestSeen);
    }

    return _EntityOutcome(
      inserted: inserted,
      updated: updated,
      tombstoned: tombstoned,
      unchanged: unchanged,
      pages: pages,
      issues: issues,
      dataVersion: dataVersion,
    );
  }

  // -------------------------------------------------------------------------
  // Per-entity apply steps
  // -------------------------------------------------------------------------

  Future<_ApplyCounts> _applyOrganizations(SyncPage<OrganizationDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        final existed = await _exists(
          db.organizations,
          db.organizations.id,
          dto.id,
        );
        await db
            .into(db.organizations)
            .insertOnConflictUpdate(DtoMappers.organization(dto));
        await _recordIdentity(dto, 'organization', dto.id);
        existed ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      final tombstoned = await _applyTombstones(
        page: page,
        entityType: 'organization',
        presentIds: page.items.map((e) => e.id).toSet(),
        markDeleted: (id, at) =>
            (db.update(db.organizations)..where((t) => t.id.equals(id))).write(
              OrganizationsCompanion(deletedAt: Value(at)),
            ),
        allIdsForSource: () => _idsForSource(
          db.organizations,
          db.organizations.id,
          db.organizations.sourceName,
          db.organizations.deletedAt,
          page.sourceName,
        ),
      );
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        tombstoned: tombstoned,
        newestTimestamp: newest,
      );
    });
  }

  Future<_ApplyCounts> _applyVenues(SyncPage<VenueDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        final existed = await _exists(db.venues, db.venues.id, dto.id);
        await db.into(db.venues).insertOnConflictUpdate(DtoMappers.venue(dto));
        await _recordIdentity(dto, 'venue', dto.id);
        existed ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      final tombstoned = await _applyTombstones(
        page: page,
        entityType: 'venue',
        presentIds: page.items.map((e) => e.id).toSet(),
        markDeleted: (id, at) =>
            (db.update(db.venues)..where((t) => t.id.equals(id))).write(
              VenuesCompanion(deletedAt: Value(at)),
            ),
        allIdsForSource: () => _idsForSource(
          db.venues,
          db.venues.id,
          db.venues.sourceName,
          db.venues.deletedAt,
          page.sourceName,
        ),
      );
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        tombstoned: tombstoned,
        newestTimestamp: newest,
      );
    });
  }

  Future<_ApplyCounts> _applyTeams(SyncPage<TeamDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        final previous = await (db.select(
          db.teams,
        )..where((t) => t.id.equals(dto.id))).getSingleOrNull();

        await db.into(db.teams).insertOnConflictUpdate(DtoMappers.team(dto));

        // A team rename is a fact worth keeping: it explains why an old
        // result shows a different name.
        if (previous != null && previous.name != dto.name) {
          await _recordRevision(
            entityType: 'team',
            entityId: dto.id,
            field: 'name',
            previous: previous.name,
            next: dto.name,
            sourceName: dto.source.sourceName,
            reason: 'rename',
          );
        }

        // Aliases are replaced wholesale for this team: the source is
        // authoritative about which spellings it knows.
        await (db.delete(
          db.teamAliases,
        )..where((t) => t.teamId.equals(dto.id))).go();
        await db.batch((b) {
          b.insertAll(
            db.teamAliases,
            DtoMappers.teamAliases(dto),
            mode: InsertMode.insertOrReplace,
          );
        });

        await _recordIdentity(dto, 'team', dto.id);
        previous != null ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      final tombstoned = await _applyTombstones(
        page: page,
        entityType: 'team',
        presentIds: page.items.map((e) => e.id).toSet(),
        markDeleted: (id, at) =>
            (db.update(db.teams)..where((t) => t.id.equals(id))).write(
              TeamsCompanion(deletedAt: Value(at)),
            ),
        allIdsForSource: () => _idsForSource(
          db.teams,
          db.teams.id,
          db.teams.sourceName,
          db.teams.deletedAt,
          page.sourceName,
        ),
      );
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        tombstoned: tombstoned,
        newestTimestamp: newest,
      );
    });
  }

  Future<_ApplyCounts> _applyCompetitions(SyncPage<CompetitionDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        final existed = await _exists(
          db.competitions,
          db.competitions.id,
          dto.id,
        );
        await db
            .into(db.competitions)
            .insertOnConflictUpdate(DtoMappers.competition(dto));

        for (final season in dto.seasons) {
          await db
              .into(db.seasons)
              .insertOnConflictUpdate(DtoMappers.season(season, dto.source));
          for (final stage in season.stages) {
            await db
                .into(db.stages)
                .insertOnConflictUpdate(DtoMappers.stage(stage, dto.source));
          }
        }

        await _recordIdentity(dto, 'competition', dto.id);
        existed ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      final tombstoned = await _applyTombstones(
        page: page,
        entityType: 'competition',
        presentIds: page.items.map((e) => e.id).toSet(),
        markDeleted: (id, at) =>
            (db.update(db.competitions)..where((t) => t.id.equals(id))).write(
              CompetitionsCompanion(deletedAt: Value(at)),
            ),
        allIdsForSource: () => _idsForSource(
          db.competitions,
          db.competitions.id,
          db.competitions.sourceName,
          db.competitions.deletedAt,
          page.sourceName,
        ),
      );
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        tombstoned: tombstoned,
        newestTimestamp: newest,
      );
    });
  }

  Future<_ApplyCounts> _applyPeople(SyncPage<PersonDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        final existed = await _exists(db.people, db.people.id, dto.id);
        await db.into(db.people).insertOnConflictUpdate(DtoMappers.person(dto));
        await (db.delete(
          db.personAliases,
        )..where((t) => t.personId.equals(dto.id))).go();
        await db.batch((b) {
          b.insertAll(
            db.personAliases,
            DtoMappers.personAliases(dto),
            mode: InsertMode.insertOrReplace,
          );
        });
        await _recordIdentity(dto, 'person', dto.id);
        existed ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        newestTimestamp: newest,
      );
    });
  }

  Future<_ApplyCounts> _applyRoster(SyncPage<RosterEntryDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        // A roster entry implies the team took part in that season, so we
        // materialise the TeamSeason join rather than dropping the row.
        final teamSeasonId = '${dto.teamId}__${dto.seasonId}';
        await db
            .into(db.teamSeasons)
            .insertOnConflictUpdate(
              DtoMappers.teamSeason(
                id: teamSeasonId,
                teamId: dto.teamId,
                seasonId: dto.seasonId,
                source: dto.source,
              ),
            );
        final existed = await _exists(
          db.rosterEntries,
          db.rosterEntries.id,
          dto.id,
        );
        await db
            .into(db.rosterEntries)
            .insertOnConflictUpdate(DtoMappers.rosterEntry(dto, teamSeasonId));
        existed ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        newestTimestamp: newest,
      );
    });
  }

  Future<_ApplyCounts> _applyGames(SyncPage<GameDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;

      for (final dto in page.items) {
        final previous = await (db.select(
          db.games,
        )..where((t) => t.id.equals(dto.id))).getSingleOrNull();

        // Duplicate detection across sources: the same fixture arriving under
        // a different id collapses onto the record we already hold.
        if (previous == null) {
          final probe = DtoMappers.game(dto);
          final dupKey = probe.dedupeKey.value;
          final duplicate =
              await (db.select(db.games)
                    ..where(
                      (t) =>
                          t.dedupeKey.equals(dupKey) &
                          t.id.equals(dto.id).not(),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          if (duplicate != null) {
            await db
                .into(db.externalIdentities)
                .insertOnConflictUpdate(
                  ExternalIdentitiesCompanion.insert(
                    sourceName: dto.source.sourceName,
                    entityType: 'game',
                    sourceRecordId: dto.source.sourceRecordId ?? dto.id,
                    canonicalId: duplicate.id,
                    firstSeenAt: dto.source.fetchedAt,
                    lastSeenAt: dto.source.fetchedAt,
                  ),
                );
            // Keep the incumbent; a later SourcePolicy pass decides whether the
            // challenger's values should win field by field.
            continue;
          }
        }

        await db.into(db.games).insertOnConflictUpdate(DtoMappers.game(dto));

        if (previous != null) {
          await _recordGameChanges(previous, dto);
        }

        // Box score is replaced wholesale — a corrected sheet supersedes the
        // old one rather than merging with it.
        final line = DtoMappers.lineScore(dto);
        if (line != null) {
          await db.into(db.gameLineScores).insertOnConflictUpdate(line);
        }
        if (dto.batting.isNotEmpty) {
          await (db.delete(
            db.battingStats,
          )..where((t) => t.gameId.equals(dto.id))).go();
          await db.batch(
            (b) => b.insertAll(
              db.battingStats,
              DtoMappers.batting(dto),
              mode: InsertMode.insertOrReplace,
            ),
          );
        }
        if (dto.pitching.isNotEmpty) {
          await (db.delete(
            db.pitchingStats,
          )..where((t) => t.gameId.equals(dto.id))).go();
          await db.batch(
            (b) => b.insertAll(
              db.pitchingStats,
              DtoMappers.pitching(dto),
              mode: InsertMode.insertOrReplace,
            ),
          );
        }

        await _recordIdentity(dto, 'game', dto.id);
        previous != null ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }

      // Snapshot semantics apply per month partition, not globally, so an
      // August snapshot never tombstones September fixtures.
      var tombstoned = 0;
      if (page.payloadKind == SyncPayloadKind.snapshot) {
        final months = page.items.map((g) => _monthOf(g)).toSet();
        for (final month in months) {
          final present = page.items
              .where((g) => _monthOf(g) == month)
              .map((g) => g.id)
              .toSet();
          final stored =
              await (db.select(db.games)..where(
                    (t) =>
                        t.monthKey.equals(month) &
                        t.sourceName.equals(page.sourceName) &
                        t.deletedAt.isNull(),
                  ))
                  .get();
          for (final row in stored) {
            if (present.contains(row.id)) continue;
            await (db.update(db.games)..where((t) => t.id.equals(row.id)))
                .write(GamesCompanion(deletedAt: Value(_clock().toUtc())));
            await _recordRevision(
              entityType: 'game',
              entityId: row.id,
              field: 'deletedAt',
              previous: null,
              next: _clock().toUtc().toIso8601String(),
              sourceName: page.sourceName,
              reason: 'tombstone',
            );
            tombstoned++;
          }
        }
      }
      tombstoned += await _applyExplicitTombstones(
        page: page,
        entityType: 'game',
        markDeleted: (id, at) =>
            (db.update(db.games)..where((t) => t.id.equals(id))).write(
              GamesCompanion(deletedAt: Value(at)),
            ),
      );

      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        tombstoned: tombstoned,
        newestTimestamp: newest,
      );
    });
  }

  /// Records the changes a user would actually want explained: a moved
  /// fixture, a changed status, or a corrected final score.
  Future<void> _recordGameChanges(GameRow previous, GameDto dto) async {
    if (previous.status != dto.status) {
      await _recordRevision(
        entityType: 'game',
        entityId: dto.id,
        field: 'status',
        previous: previous.status,
        next: dto.status,
        sourceName: dto.source.sourceName,
        reason: 'status-change',
      );
    }
    if (!previous.startTimeUtc.isAtSameMomentAs(dto.startTime.toUtc())) {
      await _recordRevision(
        entityType: 'game',
        entityId: dto.id,
        field: 'startTimeUtc',
        previous: previous.startTimeUtc.toIso8601String(),
        next: dto.startTime.toUtc().toIso8601String(),
        sourceName: dto.source.sourceName,
        reason: 'schedule-change',
      );
    }
    // A score changing after a game was already final is a correction, which
    // is a different and more serious thing than a score first appearing.
    final wasFinal = GameStatus.parse(previous.status).hasResult;
    final scoreChanged =
        previous.homeScore != dto.homeScore ||
        previous.awayScore != dto.awayScore;
    if (wasFinal && scoreChanged) {
      await _recordRevision(
        entityType: 'game',
        entityId: dto.id,
        field: 'score',
        previous: '${previous.homeScore}-${previous.awayScore}',
        next: '${dto.homeScore}-${dto.awayScore}',
        sourceName: dto.source.sourceName,
        reason: 'result-correction',
      );
    }
  }

  Future<_ApplyCounts> _applyStandings(SyncPage<StandingDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        // Carry the previous rank forward so the UI can show movement without
        // re-deriving it from history on every read.
        final previous =
            await (db.select(db.standings)
                  ..where(
                    (t) =>
                        t.seasonId.equals(dto.seasonId) &
                        t.teamId.equals(dto.teamId),
                  )
                  ..orderBy([(t) => OrderingTerm.desc(t.capturedAt)])
                  ..limit(1))
                .getSingleOrNull();

        final priorRank = (previous != null && previous.rank != dto.rank)
            ? previous.rank
            : previous?.previousRank;

        final existed = await _exists(db.standings, db.standings.id, dto.id);
        await db
            .into(db.standings)
            .insertOnConflictUpdate(
              DtoMappers.standing(dto, previousRank: priorRank),
            );
        existed ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        newestTimestamp: newest,
      );
    });
  }

  Future<_ApplyCounts> _applyArticles(SyncPage<ArticleDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        final existed = await _exists(db.articles, db.articles.id, dto.id);
        await db
            .into(db.articles)
            .insertOnConflictUpdate(DtoMappers.article(dto));
        existed ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        newestTimestamp: newest,
      );
    });
  }

  Future<_ApplyCounts> _applyVideos(SyncPage<VideoDto> page) {
    return db.transaction(() async {
      var inserted = 0;
      var updated = 0;
      DateTime? newest;
      for (final dto in page.items) {
        final existed = await _exists(db.videos, db.videos.id, dto.id);
        await db.into(db.videos).insertOnConflictUpdate(DtoMappers.video(dto));
        existed ? updated++ : inserted++;
        newest = _later(newest, dto.source.fetchedAt);
      }
      return _ApplyCounts(
        inserted: inserted,
        updated: updated,
        newestTimestamp: newest,
      );
    });
  }

  // -------------------------------------------------------------------------
  // Shared helpers
  // -------------------------------------------------------------------------

  static String _monthOf(GameDto dto) {
    final companion = DtoMappers.game(dto);
    return companion.monthKey.value;
  }

  Future<bool> _exists<T extends Table, D>(
    TableInfo<T, D> table,
    GeneratedColumn<String> idColumn,
    String id,
  ) async {
    final query = db.selectOnly(table)
      ..addColumns([idColumn])
      ..where(idColumn.equals(id))
      ..limit(1);
    return await query.getSingleOrNull() != null;
  }

  Future<List<String>> _idsForSource<T extends Table, D>(
    TableInfo<T, D> table,
    GeneratedColumn<String> idColumn,
    GeneratedColumn<String> sourceColumn,
    GeneratedColumn<DateTime> deletedColumn,
    String sourceName,
  ) async {
    final query = db.selectOnly(table)
      ..addColumns([idColumn])
      ..where(sourceColumn.equals(sourceName) & deletedColumn.isNull());
    final rows = await query.get();
    return rows.map((r) => r.read(idColumn)!).toList(growable: false);
  }

  /// Snapshot semantics: anything this source previously supplied that is
  /// absent from a full snapshot is tombstoned. Never applied to a delta.
  Future<int> _applyTombstones<T>({
    required SyncPage<T> page,
    required String entityType,
    required Set<String> presentIds,
    required Future<void> Function(String id, DateTime at) markDeleted,
    required Future<List<String>> Function() allIdsForSource,
  }) async {
    var count = 0;
    if (page.payloadKind == SyncPayloadKind.snapshot) {
      final stored = await allIdsForSource();
      final now = _clock().toUtc();
      for (final id in stored) {
        if (presentIds.contains(id)) continue;
        await markDeleted(id, now);
        await _recordRevision(
          entityType: entityType,
          entityId: id,
          field: 'deletedAt',
          previous: null,
          next: now.toIso8601String(),
          sourceName: page.sourceName,
          reason: 'tombstone',
        );
        count++;
      }
    }
    count += await _applyExplicitTombstones(
      page: page,
      entityType: entityType,
      markDeleted: markDeleted,
    );
    return count;
  }

  /// Records the source explicitly declared gone, regardless of payload kind.
  Future<int> _applyExplicitTombstones<T>({
    required SyncPage<T> page,
    required String entityType,
    required Future<void> Function(String id, DateTime at) markDeleted,
  }) async {
    if (page.tombstonedSourceRecordIds.isEmpty) return 0;
    final now = _clock().toUtc();
    var count = 0;
    for (final sourceRecordId in page.tombstonedSourceRecordIds) {
      final canonical = await _resolveCanonicalId(
        page.sourceName,
        entityType,
        sourceRecordId,
      );
      if (canonical == null) continue;
      await markDeleted(canonical, now);
      await _recordRevision(
        entityType: entityType,
        entityId: canonical,
        field: 'deletedAt',
        previous: null,
        next: now.toIso8601String(),
        sourceName: page.sourceName,
        reason: 'tombstone',
      );
      count++;
    }
    return count;
  }

  /// Maps a source's own record id to our canonical id, following merges.
  Future<String?> _resolveCanonicalId(
    String sourceName,
    String entityType,
    String sourceRecordId,
  ) async {
    final row =
        await (db.select(db.externalIdentities)..where(
              (t) =>
                  t.sourceName.equals(sourceName) &
                  t.entityType.equals(entityType) &
                  t.sourceRecordId.equals(sourceRecordId),
            ))
            .getSingleOrNull();
    if (row == null) {
      // Sources that use our ids directly need no mapping row.
      return sourceRecordId;
    }
    return row.mergedIntoCanonicalId ?? row.canonicalId;
  }

  Future<void> _recordIdentity(
    EntityDto dto,
    String entityType,
    String canonicalId,
  ) async {
    final sourceRecordId = dto.sourceRecordId;
    if (sourceRecordId == null || sourceRecordId.isEmpty) return;
    final existing =
        await (db.select(db.externalIdentities)..where(
              (t) =>
                  t.sourceName.equals(dto.source.sourceName) &
                  t.entityType.equals(entityType) &
                  t.sourceRecordId.equals(sourceRecordId),
            ))
            .getSingleOrNull();
    await db
        .into(db.externalIdentities)
        .insertOnConflictUpdate(
          ExternalIdentitiesCompanion.insert(
            sourceName: dto.source.sourceName,
            entityType: entityType,
            sourceRecordId: sourceRecordId,
            canonicalId: canonicalId,
            firstSeenAt: existing?.firstSeenAt ?? dto.source.fetchedAt,
            lastSeenAt: dto.source.fetchedAt,
            mergedIntoCanonicalId: Value(existing?.mergedIntoCanonicalId),
          ),
        );
  }

  Future<void> _recordRevision({
    required String entityType,
    required String entityId,
    required String field,
    required String? previous,
    required String? next,
    required String sourceName,
    String? reason,
  }) async {
    await db
        .into(db.entityRevisions)
        .insert(
          EntityRevisionsCompanion.insert(
            id: _nextId('rev'),
            entityType: entityType,
            entityId: entityId,
            fieldName: field,
            changedAt: _clock().toUtc(),
            sourceName: sourceName,
            previousValue: Value(previous),
            newValue: Value(next),
            reason: Value(reason),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> _finishRun(String runId, SyncResult result) async {
    await (db.update(db.syncRuns)..where((t) => t.id.equals(runId))).write(
      SyncRunsCompanion(
        finishedAt: Value(result.finishedAt),
        inserted: Value(result.inserted),
        updated: Value(result.updated),
        tombstoned: Value(result.tombstoned),
        unchanged: Value(result.unchanged),
        pagesFetched: Value(result.pagesFetched),
        failureKind: Value(result.isSuccess ? null : result.failure.name),
        failureMessage: Value(result.failureMessage),
        dataVersion: Value(result.dataVersion),
        skippedNotModified: Value(result.skippedBecauseNotModified),
      ),
    );

    if (result.issues.isEmpty) return;
    final now = _clock().toUtc();
    await db.batch((b) {
      b.insertAll(
        db.syncErrors,
        result.issues
            // Keep the log bounded: a badly broken feed should not write
            // thousands of rows on every refresh.
            .take(200)
            .map(
              (i) => SyncErrorsCompanion.insert(
                syncRunId: runId,
                sourceName: i.sourceName,
                entityType: i.entityType,
                severity: i.severity.name,
                message: i.message,
                sourceRecordId: Value(i.sourceRecordId),
                field: Value(i.field),
                occurredAt: now,
              ),
            )
            .toList(growable: false),
      );
    });
  }

  static String _watermarkKey(
    String sourceName,
    SyncEntityType entity,
    String? scopeKey,
  ) => 'watermark|$sourceName|${entity.storageKey}|${scopeKey ?? '-'}';

  Future<DateTime?> _readWatermark(String key) async {
    final row = await (db.select(
      db.syncStates,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    final raw = row?.value;
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> _writeWatermark(String key, DateTime value) async {
    await db
        .into(db.syncStates)
        .insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            key: key,
            value: Value(value.toUtc().toIso8601String()),
            updatedAt: _clock().toUtc(),
          ),
        );
  }

  static DateTime? _later(DateTime? a, DateTime b) =>
      a == null || b.isAfter(a) ? b : a;

  String _nextId(String prefix) =>
      '$prefix-${_clock().toUtc().microsecondsSinceEpoch}-${_idCounter++}';
}

class _ApplyCounts {
  const _ApplyCounts({
    this.inserted = 0,
    this.updated = 0,
    this.tombstoned = 0,
    this.newestTimestamp,
  });

  final int inserted;
  final int updated;
  final int tombstoned;
  final DateTime? newestTimestamp;
}

class _EntityOutcome {
  const _EntityOutcome({
    required this.inserted,
    required this.updated,
    required this.tombstoned,
    required this.unchanged,
    required this.pages,
    required this.issues,
    this.dataVersion,
  });

  final int inserted;
  final int updated;
  final int tombstoned;
  final int unchanged;
  final int pages;
  final List<SyncIssue> issues;
  final String? dataVersion;
}
