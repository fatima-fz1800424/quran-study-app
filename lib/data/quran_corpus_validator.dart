const int kExpectedSurahCount = 114;
const int kExpectedAyahCount = 6236;
const String kQuranChaptersEndpoint =
    'https://api.quran.com/api/v4/chapters?language=en';
const String kQuranUthmaniEndpoint =
    'https://api.quran.com/api/v4/quran/verses/uthmani?chapter_number={chapter_number}';
const String kQuranEditionIdentifier = 'quran-uthmani';
const String kQuranEditionName = 'Uthmani';

const Set<String> kMuqattaatExceptions = {
  '2:1',
  '3:1',
  '7:1',
  '19:1',
  '20:1',
  '26:1',
  '28:1',
  '29:1',
  '30:1',
  '31:1',
  '32:1',
  '36:1',
  '40:1',
  '41:1',
  '42:1',
  '42:2',
  '43:1',
  '44:1',
  '45:1',
  '46:1',
};

bool containsArabicDiacritic(String text) {
  return RegExp(r'[\u064B-\u0652]').hasMatch(text);
}

bool isMuqattaatOpeningReference(String verseKey) {
  return kMuqattaatExceptions.contains(verseKey);
}

void validateArabicAyahText(String text, {String? label, String? verseKey}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw StateError('${label ?? 'Ayah text'} is empty or whitespace-only.');
  }

  final isException = verseKey != null && kMuqattaatExceptions.contains(verseKey);
  if (!containsArabicDiacritic(trimmed)) {
    if (!isException) {
      throw StateError(
        '${label ?? 'Ayah text'} does not contain an Arabic diacritic character.',
      );
    }

    if (!isMuqattaatOpeningReference(verseKey!)) {
      throw StateError(
        'Exempted ayah $verseKey is not a recognized muqatta’at opening.',
      );
    }
  }

  if (RegExp(r'[A-Za-z]').hasMatch(trimmed)) {
    throw StateError(
      '${label ?? 'Ayah text'} contains Latin letters and is invalid.',
    );
  }
}

void validateSourceChapterCounts(
  Map<int, int> chapterCounts, {
  required int expectedTotal,
}) {
  if (chapterCounts.length != kExpectedSurahCount) {
    throw StateError(
      'Expected $kExpectedSurahCount chapter entries, got ${chapterCounts.length}.',
    );
  }

  final total = chapterCounts.values.fold<int>(0, (sum, count) => sum + count);
  if (total != expectedTotal) {
    throw StateError(
      'Expected chapter totals to sum to $expectedTotal, but the fetched source summed to $total.',
    );
  }
}

void validateImportedChapterCounts({
  required Map<int, int> sourceChapterCounts,
  required Map<int, int> importedChapterCounts,
}) {
  if (sourceChapterCounts.length != importedChapterCounts.length) {
    throw StateError(
      'Source chapter count (${sourceChapterCounts.length}) does not match imported chapter count (${importedChapterCounts.length}).',
    );
  }

  for (final entry in sourceChapterCounts.entries) {
    final surahNumber = entry.key;
    final expectedCount = entry.value;
    final observedCount = importedChapterCounts[surahNumber] ?? 0;

    if (observedCount != expectedCount) {
      throw StateError(
        'Surah $surahNumber mismatch: chapters endpoint says $expectedCount ayahs, imported database has $observedCount.',
      );
    }
  }
}

void validateCorpusTotals({
  required int observedAyahCount,
  required int expectedAyahCount,
}) {
  if (observedAyahCount != expectedAyahCount) {
    throw StateError(
      'Expected $expectedAyahCount ayahs after import, got $observedAyahCount.',
    );
  }
}
