/// Korean-aware text handling for search and display.
///
/// Two things Korean users expect that a naive `contains` does not give them:
///  * **초성 검색** — typing `ㅅㅇ` should find `서울`.
///  * **띄어쓰기 무시** — `서울다이아몬드` should find `서울 다이아몬드`.
///
/// Both are handled by pre-computing a search key at write time (stored in
/// `teams.search_key` etc.) and normalising the query the same way at read
/// time, so lookups stay a plain indexed `LIKE` rather than a scan.
class KoreanText {
  const KoreanText._();

  static const int _hangulBase = 0xAC00;
  static const int _hangulEnd = 0xD7A3;
  static const int _jamoPerLead = 588; // 21 vowels × 28 finals

  /// The 19 lead consonants, in Unicode order.
  static const List<String> leadConsonants = <String>[
    'ㄱ',
    'ㄲ',
    'ㄴ',
    'ㄷ',
    'ㄸ',
    'ㄹ',
    'ㅁ',
    'ㅂ',
    'ㅃ',
    'ㅅ',
    'ㅆ',
    'ㅇ',
    'ㅈ',
    'ㅉ',
    'ㅊ',
    'ㅋ',
    'ㅌ',
    'ㅍ',
    'ㅎ',
  ];

  /// Compatibility jamo that a user can actually type, mapped to the lead
  /// consonant they represent. Double consonants are kept distinct.
  static const Set<String> _typableJamo = <String>{
    'ㄱ',
    'ㄲ',
    'ㄴ',
    'ㄷ',
    'ㄸ',
    'ㄹ',
    'ㅁ',
    'ㅂ',
    'ㅃ',
    'ㅅ',
    'ㅆ',
    'ㅇ',
    'ㅈ',
    'ㅉ',
    'ㅊ',
    'ㅋ',
    'ㅌ',
    'ㅍ',
    'ㅎ',
  };

  static bool isSyllable(int codeUnit) =>
      codeUnit >= _hangulBase && codeUnit <= _hangulEnd;

  static bool isJamo(String char) => _typableJamo.contains(char);

  /// The lead consonant of a single Hangul syllable, or the character itself
  /// if it is not a syllable.
  static String leadOf(String char) {
    if (char.isEmpty) return char;
    final code = char.codeUnitAt(0);
    if (!isSyllable(code)) return char;
    return leadConsonants[(code - _hangulBase) ~/ _jamoPerLead];
  }

  /// Extracts the 초성 string: `서울 다이아몬드` → `ㅅㅇㄷㅇㅇㅁㄷ`.
  ///
  /// Non-Hangul characters are kept (lower-cased) so a mixed name like
  /// `WBAK 서울` still yields something searchable.
  static String initials(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (_isWhitespace(char)) continue;
      if (isSyllable(rune)) {
        buffer.write(leadConsonants[(rune - _hangulBase) ~/ _jamoPerLead]);
      } else if (isJamo(char)) {
        buffer.write(char);
      } else {
        buffer.write(char.toLowerCase());
      }
    }
    return buffer.toString();
  }

  /// Case-folded, whitespace- and punctuation-stripped form used for alias
  /// matching and partial search.
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (_isWhitespace(char) || _isPunctuation(char)) continue;
      buffer.write(char.toLowerCase());
    }
    return buffer.toString();
  }

  /// The value stored in a `search_key` column.
  ///
  /// Concatenates the normalised name and its initials with a separator, so a
  /// single `LIKE '%q%'` matches either form.
  static String searchKey(String name, {Iterable<String> aliases = const []}) {
    final parts = <String>{normalize(name), initials(name)};
    for (final alias in aliases) {
      if (alias.trim().isEmpty) continue;
      parts.add(normalize(alias));
      parts.add(initials(alias));
    }
    return parts.where((p) => p.isNotEmpty).join('|');
  }

  /// Normalises a user's query the same way, so it can be matched against a
  /// stored [searchKey].
  ///
  /// A query made only of jamo (`ㅅㅇ`) is matched as initials; anything else
  /// is matched as normalised text. Both live in the same key, so one `LIKE`
  /// covers it.
  static String queryKey(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return '';
    final onlyJamo = trimmed.runes.every((r) {
      final c = String.fromCharCode(r);
      return isJamo(c) || _isWhitespace(c);
    });
    return onlyJamo ? initials(trimmed) : normalize(trimmed);
  }

  /// In-memory match used by tests and by small collections that are already
  /// loaded. The SQL path uses the same key, so results agree.
  static bool matches(
    String candidate,
    String query, {
    Iterable<String> aliases = const [],
  }) {
    final q = queryKey(query);
    if (q.isEmpty) return true;
    return searchKey(candidate, aliases: aliases).contains(q);
  }

  /// Ranks a hit so exact and prefix matches sort above mid-string ones.
  static int score(String candidate, String query) {
    final q = queryKey(query);
    if (q.isEmpty) return 0;
    final normalized = normalize(candidate);
    final chosung = initials(candidate);
    if (normalized == q) return 100;
    if (normalized.startsWith(q)) return 80;
    if (chosung == q) return 70;
    if (chosung.startsWith(q)) return 60;
    if (normalized.contains(q)) return 40;
    if (chosung.contains(q)) return 30;
    return 0;
  }

  static bool _isWhitespace(String char) =>
      char == ' ' || char == '\t' || char == '\n' || char == ' ';

  static bool _isPunctuation(String char) => const <String>{
    '.',
    ',',
    '-',
    '_',
    '(',
    ')',
    '[',
    ']',
    '·',
    '/',
    "'",
    '"',
  }.contains(char);

  /// Korean particle selection: `팀을` vs `선수를`.
  ///
  /// Picks the object-marker form that matches whether the preceding syllable
  /// ends in a consonant. Used for grammatical UI copy rather than dodging the
  /// problem with awkward phrasing.
  static String objectParticle(String word) =>
      _endsWithFinalConsonant(word) ? '을' : '를';

  /// `팀이` vs `선수가`.
  static String subjectParticle(String word) =>
      _endsWithFinalConsonant(word) ? '이' : '가';

  /// `팀은` vs `선수는`.
  static String topicParticle(String word) =>
      _endsWithFinalConsonant(word) ? '은' : '는';

  /// `구장으로` vs `서울로`.
  static String directionParticle(String word) {
    if (word.isEmpty) return '로';
    final code = word.codeUnitAt(word.length - 1);
    if (!isSyllable(code)) return '로';
    final finalIndex = (code - _hangulBase) % 28;
    // ㄹ (index 8) takes 로, every other final consonant takes 으로.
    if (finalIndex == 0 || finalIndex == 8) return '로';
    return '으로';
  }

  static bool _endsWithFinalConsonant(String word) {
    if (word.isEmpty) return false;
    final code = word.codeUnitAt(word.length - 1);
    if (!isSyllable(code)) {
      // Latin letters and digits: fall back to a reasonable default.
      return RegExp(r'[0-9a-zA-Z]$').hasMatch(word);
    }
    return (code - _hangulBase) % 28 != 0;
  }
}
