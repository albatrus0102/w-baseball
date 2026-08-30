import 'package:meta/meta.dart';

/// How confident are we in this record?
enum QualityStatus {
  /// Passed automated validation only.
  autoVerified,

  /// A human checked it against the official record.
  humanVerified,

  /// Sources disagree, or a correction is open against it.
  disputed;

  static QualityStatus parse(String? raw) => switch (raw) {
    'humanVerified' => QualityStatus.humanVerified,
    'disputed' => QualityStatus.disputed,
    _ => QualityStatus.autoVerified,
  };

  String get wireValue => name;
}

/// What we are allowed to do with the content.
enum LicenseStatus {
  /// We may store and display the content itself.
  permitted,

  /// We may store metadata and link out, but must not reproduce the body,
  /// photos, or article images.
  linkOnly,

  /// Not yet cleared. Personal data with this status must never be published.
  unknown;

  static LicenseStatus parse(String? raw) => switch (raw) {
    'permitted' => LicenseStatus.permitted,
    'linkOnly' => LicenseStatus.linkOnly,
    _ => LicenseStatus.unknown,
  };

  String get wireValue => name;
}

enum RecordVisibility {
  public,
  private,
  hidden;

  static RecordVisibility parse(String? raw) => switch (raw) {
    'private' => RecordVisibility.private,
    'hidden' => RecordVisibility.hidden,
    _ => RecordVisibility.public,
  };

  String get wireValue => name;
}

/// Provenance metadata carried by every publishable entity.
///
/// The publish pipeline refuses to emit a record without `sourceName`,
/// `sourceUrl`, and `fetchedAt`, and refuses to emit personal data whose
/// [licenseStatus] is [LicenseStatus.unknown].
@immutable
class Provenance {
  const Provenance({
    required this.sourceName,
    required this.sourceUrl,
    required this.fetchedAt,
    this.sourceRecordId,
    this.verifiedAt,
    this.contentHash,
    this.qualityStatus = QualityStatus.autoVerified,
    this.licenseStatus = LicenseStatus.unknown,
    this.visibility = RecordVisibility.public,
    this.isDemo = false,
  });

  /// Stable key of the origin, e.g. `wbak`, `kbsa`, `wbsc`, `wpbl`,
  /// `manual-submission`, or `seed-demo`.
  final String sourceName;

  /// The exact page a human can open to check this record. Not a site home
  /// page — the deep detail URL.
  final String sourceUrl;

  final DateTime fetchedAt;
  final String? sourceRecordId;
  final DateTime? verifiedAt;
  final String? contentHash;
  final QualityStatus qualityStatus;
  final LicenseStatus licenseStatus;
  final RecordVisibility visibility;

  /// True for illustrative sample data. Demo records are labelled in the UI
  /// and are blocked from the production manifest by `scripts/validate`.
  final bool isDemo;

  /// The timestamp a user cares about: when we last had reason to trust the
  /// record. A human check if there was one, otherwise the fetch.
  DateTime get lastConfirmedAt => verifiedAt ?? fetchedAt;

  /// Whether [lastConfirmedAt] means a person checked this, or just that we
  /// downloaded it.
  ///
  /// `verifiedAt` is the only field that says anyone looked. Since the review
  /// ledger landed, no generated record carries one — so a line that reads
  /// "방금 확인" over `lastConfirmedAt` is telling the user a record was
  /// confirmed when all that happened was a file download. That is the same
  /// overstatement the ledger was introduced to remove, made again in wording
  /// instead of in data.
  bool get isHumanConfirmed => verifiedAt != null;

  bool isStale(DateTime now, Duration threshold) =>
      now.difference(lastConfirmedAt) > threshold;

  /// Content itself may only be reproduced when explicitly permitted.
  bool get canReproduceContent => licenseStatus == LicenseStatus.permitted;

  Provenance copyWith({
    String? sourceName,
    String? sourceUrl,
    DateTime? fetchedAt,
    String? sourceRecordId,
    DateTime? verifiedAt,
    String? contentHash,
    QualityStatus? qualityStatus,
    LicenseStatus? licenseStatus,
    RecordVisibility? visibility,
    bool? isDemo,
  }) {
    return Provenance(
      sourceName: sourceName ?? this.sourceName,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      sourceRecordId: sourceRecordId ?? this.sourceRecordId,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      contentHash: contentHash ?? this.contentHash,
      qualityStatus: qualityStatus ?? this.qualityStatus,
      licenseStatus: licenseStatus ?? this.licenseStatus,
      visibility: visibility ?? this.visibility,
      isDemo: isDemo ?? this.isDemo,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Provenance &&
          other.sourceName == sourceName &&
          other.sourceUrl == sourceUrl &&
          other.fetchedAt == fetchedAt &&
          other.sourceRecordId == sourceRecordId &&
          other.verifiedAt == verifiedAt &&
          other.contentHash == contentHash &&
          other.qualityStatus == qualityStatus &&
          other.licenseStatus == licenseStatus &&
          other.visibility == visibility &&
          other.isDemo == isDemo;

  @override
  int get hashCode => Object.hash(
    sourceName,
    sourceUrl,
    fetchedAt,
    sourceRecordId,
    verifiedAt,
    contentHash,
    qualityStatus,
    licenseStatus,
    visibility,
    isDemo,
  );
}

/// Per-field attribution, so a game whose score came from KBSA but whose venue
/// came from a public facilities dataset can be explained field by field.
/// The schema and storage exist now; the UI surfaces it only on demand.
@immutable
class FieldProvenance {
  const FieldProvenance({
    required this.entityType,
    required this.entityId,
    required this.fieldName,
    required this.sourceName,
    required this.sourceUrl,
    required this.observedAt,
  });

  final String entityType;
  final String entityId;
  final String fieldName;
  final String sourceName;
  final String sourceUrl;
  final DateTime observedAt;
}

/// Conflict-resolution policy between sources.
///
/// Deliberately data, not code: priorities live in a table so a new official
/// feed can outrank a scraped one without an app release.
@immutable
class SourcePolicy {
  const SourcePolicy({
    required this.sourceName,
    required this.officialRank,
    required this.trustsHumanReview,
    this.enabled = true,
  });

  /// Lower is more authoritative (0 = governing body's own record).
  final int officialRank;
  final String sourceName;

  /// Whether a human-verified record from this source outranks a fresher
  /// auto-verified record from a more official one.
  final bool trustsHumanReview;

  final bool enabled;

  /// Decide which of two candidate values wins.
  ///
  /// Order: human review (when the policy honours it) → officialness →
  /// recency. Never "last write wins".
  static bool challengerWins({
    required SourcePolicy incumbentPolicy,
    required Provenance incumbent,
    required SourcePolicy challengerPolicy,
    required Provenance challenger,
  }) {
    final incumbentHuman =
        incumbent.qualityStatus == QualityStatus.humanVerified &&
        incumbentPolicy.trustsHumanReview;
    final challengerHuman =
        challenger.qualityStatus == QualityStatus.humanVerified &&
        challengerPolicy.trustsHumanReview;
    if (incumbentHuman != challengerHuman) return challengerHuman;

    if (incumbentPolicy.officialRank != challengerPolicy.officialRank) {
      return challengerPolicy.officialRank < incumbentPolicy.officialRank;
    }
    return challenger.lastConfirmedAt.isAfter(incumbent.lastConfirmedAt);
  }
}
