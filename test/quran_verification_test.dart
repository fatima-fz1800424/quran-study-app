import 'package:flutter_test/flutter_test.dart';

import 'package:quran_study_app/data/quran_corpus_validator.dart';

void main() {
  test('Arabic ayah text is validated with strict diacritic checks and explicit muqatta’at exceptions', () {
    expect(
      () => validateArabicAyahText('بِسْمِ ٱللَّهِ', verseKey: '1:1'),
      returnsNormally,
    );
    expect(
      () => validateArabicAyahText('بسم الله', verseKey: '1:1'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => validateArabicAyahText('الْم', verseKey: '2:1'),
      returnsNormally,
    );
    expect(() => validateArabicAyahText('', verseKey: '1:1'), throwsA(isA<StateError>()));
    expect(
      () => validateArabicAyahText('Allah says hello', verseKey: '1:1'),
      throwsA(isA<StateError>()),
    );
  });

  test('source counts and imported chapter counts must match the independent source', () {
    final validSourceCounts = <int, int>{
      for (var surahNumber = 1; surahNumber <= 114; surahNumber++)
        surahNumber: 1,
    };
    expect(
      () => validateSourceChapterCounts(validSourceCounts, expectedTotal: 114),
      returnsNormally,
    );

    final validImportedCounts = <int, int>{
      for (var surahNumber = 1; surahNumber <= 114; surahNumber++)
        surahNumber: 1,
    };
    final mismatchedImportedCounts = <int, int>{
      for (var surahNumber = 1; surahNumber <= 114; surahNumber++)
        surahNumber: surahNumber == 1 ? 2 : 1,
    };

    expect(
      () => validateImportedChapterCounts(
        sourceChapterCounts: validSourceCounts,
        importedChapterCounts: mismatchedImportedCounts,
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      () => validateImportedChapterCounts(
        sourceChapterCounts: validSourceCounts,
        importedChapterCounts: validImportedCounts,
      ),
      returnsNormally,
    );

    expect(
      () => validateCorpusTotals(
        observedAyahCount: 6235,
        expectedAyahCount: 6236,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
