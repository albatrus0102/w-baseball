import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';
import '../sync/sync_contracts.dart';
import 'json_document_data_source.dart';
import 'payload_envelope.dart';

/// Reads the data set bundled into the APK at `assets/seed/`.
///
/// This is what makes the very first launch useful with no network at all:
/// the database is populated from these files before the first frame is
/// requested, so the home screen never shows an empty shell while waiting on
/// a socket.
///
/// The bundled set is clearly-labelled demo data (`isDemo: true` on every
/// record) plus factually-verifiable public reference rows. It is never
/// presented as an official record — see `docs/data-sources.md`.
final class BundledSeedDataSource extends JsonDocumentDataSource {
  BundledSeedDataSource({
    required this.contract,
    this.bundle,
    this.assetPrefix = 'assets/seed/',
  });

  final DataContractConfig contract;

  /// Injectable for tests; defaults to the app's real asset bundle.
  final AssetBundle? bundle;

  final String assetPrefix;

  AssetBundle get _assets => bundle ?? rootBundle;

  /// Shared so callers that need to tell a real remote sync apart from a
  /// re-read of the bundle (see `providers.dart`) reference one constant
  /// rather than repeating the string `'seed'`.
  static const String seedSourceName = 'seed';

  @override
  String get sourceName => seedSourceName;

  @override
  String get displayName => '앱 기본 데이터';

  @override
  bool get isEnabled => true;

  @override
  bool supportsSchemaVersion(int schemaVersion) =>
      contract.supports(schemaVersion);

  /// Cached so a full sync does not re-read the manifest asset per entity.
  List<String>? _months;
  List<int>? _years;
  List<String>? _seasons;

  Future<void> _loadIndex() async {
    if (_months != null) return;
    final doc = await loadDocument(DataPaths.version, const SyncValidators());
    if (doc == null) {
      _months = const <String>[];
      _years = const <int>[];
      _seasons = const <String>[];
      return;
    }
    try {
      final manifest = DataManifestReader.parse(doc.body);
      _months = manifest.months;
      _years = manifest.years;
      _seasons = manifest.seasons;
    } on Object {
      // A malformed bundled index must not break the app; we simply have no
      // partitioned files to offer.
      _months = const <String>[];
      _years = const <int>[];
      _seasons = const <String>[];
    }
  }

  @override
  Future<List<String>> availableGameMonths() async {
    await _loadIndex();
    return _months ?? const <String>[];
  }

  @override
  Future<List<int>> availableCompetitionYears() async {
    await _loadIndex();
    return _years ?? const <int>[];
  }

  @override
  Future<List<String>> availableStandingSeasons() async {
    await _loadIndex();
    return _seasons ?? const <String>[];
  }

  @override
  Future<SourceDocument?> loadDocument(
    String path,
    SyncValidators validators,
  ) async {
    try {
      final body = await _assets.loadString('$assetPrefix$path');
      return SourceDocument(body: body);
    } on FlutterError {
      // Asset absent. Legitimate — a seed build need not ship every partition.
      return null;
    }
  }
}

/// Derives the partition lists from a `version.json` file listing.
///
/// Shared by the bundled and remote sources so both learn "which months
/// exist" the same way, from data rather than from a hard-coded list.
class DataManifestReader {
  const DataManifestReader._({
    required this.months,
    required this.years,
    required this.seasons,
  });

  final List<String> months;
  final List<int> years;
  final List<String> seasons;

  static final RegExp _monthPattern = RegExp(r'^games/(\d{4}-\d{2})\.json$');
  static final RegExp _yearPattern = RegExp(r'^competitions/(\d{4})\.json$');
  static final RegExp _seasonPattern = RegExp(r'^standings/(.+)\.json$');

  static DataManifestReader fromPaths(Iterable<String> paths) {
    final months = <String>[];
    final years = <int>[];
    final seasons = <String>[];
    for (final path in paths) {
      final m = _monthPattern.firstMatch(path);
      if (m != null) {
        months.add(m.group(1)!);
        continue;
      }
      final y = _yearPattern.firstMatch(path);
      if (y != null) {
        years.add(int.parse(y.group(1)!));
        continue;
      }
      final s = _seasonPattern.firstMatch(path);
      if (s != null) seasons.add(s.group(1)!);
    }
    months.sort();
    years.sort();
    seasons.sort();
    return DataManifestReader._(months: months, years: years, seasons: seasons);
  }

  static DataManifestReader parse(String versionJson) {
    final manifest = DataManifest.decode(versionJson);
    return fromPaths(manifest.files.map((f) => f.path));
  }
}
