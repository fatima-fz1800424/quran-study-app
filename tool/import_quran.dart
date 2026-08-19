import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:quran_study_app/data/quran_corpus_validator.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main() async {
  final repoRoot = p.dirname(p.dirname(Platform.script.toFilePath()));
  final assetsDir = Directory(p.join(repoRoot, 'assets'));
  if (!assetsDir.existsSync()) {
    assetsDir.createSync(recursive: true);
  }

  final chapterListResponse = await http.get(Uri.parse(kQuranChaptersEndpoint));
  if (chapterListResponse.statusCode != 200) {
    throw StateError(
      'Failed to fetch chapter list: ${chapterListResponse.statusCode}',
    );
  }

  final chapterJson =
      jsonDecode(chapterListResponse.body) as Map<String, dynamic>;
  final chapters = (chapterJson['chapters'] as List<dynamic>? ?? const []);

  if (chapters.length != kExpectedSurahCount) {
    throw StateError(
      'Expected $kExpectedSurahCount chapters, got ${chapters.length}.',
    );
  }

  final sourceChapterCounts = <int, int>{};
  for (final chapter in chapters) {
    final chapterId = chapter['id'] as int;
    final count = chapter['verses_count'] as int;
    sourceChapterCounts[chapterId] = count;
  }

  validateSourceChapterCounts(
    sourceChapterCounts,
    expectedTotal: kExpectedAyahCount,
  );

  final dbFile = File(p.join(assetsDir.path, 'quran.sqlite'));
  if (dbFile.existsSync()) {
    dbFile.deleteSync();
  }

  final db = sqlite3.open(dbFile.path);

  db.execute('''
    CREATE TABLE surahs (
      surah_number INTEGER PRIMARY KEY,
      name_arabic TEXT NOT NULL,
      name_simple TEXT NOT NULL,
      revelation_place TEXT,
      verse_count INTEGER NOT NULL
    );
  ''');

  db.execute('''
    CREATE TABLE ayahs (
      id INTEGER PRIMARY KEY,
      surah_number INTEGER NOT NULL,
      verse_number INTEGER NOT NULL,
      verse_key TEXT NOT NULL UNIQUE,
      arabic_text TEXT NOT NULL,
      character_count INTEGER NOT NULL
    );
  ''');

  final importedChapterCounts = <int, int>{};
  int observedAyahCount = 0;
  int totalCharacterCount = 0;

  for (final chapter in chapters) {
    final chapterId = chapter['id'] as int;
    final sourceCount = sourceChapterCounts[chapterId]!;
    final chapterNameArabic = chapter['name_arabic'] as String;
    final chapterSimpleName =
        (chapter['translated_name'] as Map<String, dynamic>)['name'] as String;
    final revelationPlace = chapter['revelation_place'] as String;

    final chapterResponse = await http.get(
      Uri.parse(
        kQuranUthmaniEndpoint.replaceFirst(
          '{chapter_number}',
          chapterId.toString(),
        ),
      ),
    );
    if (chapterResponse.statusCode != 200) {
      throw StateError(
        'Failed to fetch Uthmani verses for surah $chapterId: ${chapterResponse.statusCode}',
      );
    }

    final chapterBody =
        jsonDecode(chapterResponse.body) as Map<String, dynamic>;
    final verses = (chapterBody['verses'] as List<dynamic>? ?? const []);

    if (verses.length != sourceCount) {
      throw StateError(
        'Surah $chapterId mismatch: chapters endpoint says $sourceCount ayahs, fetched Uthmani endpoint has ${verses.length}.',
      );
    }

    importedChapterCounts[chapterId] = verses.length;

    db.execute(
      'INSERT INTO surahs (surah_number, name_arabic, name_simple, revelation_place, verse_count) VALUES (?, ?, ?, ?, ?)',
      [
        chapterId,
        chapterNameArabic,
        chapterSimpleName,
        revelationPlace,
        verses.length,
      ],
    );

    for (final verse in verses) {
      final verseKey = verse['verse_key'] as String;
      final text = (verse['text_uthmani'] as String? ?? '').trim();
      if (!containsArabicDiacritic(text) && kMuqattaatExceptions.contains(verseKey)) {
        if (!isMuqattaatOpeningReference(verseKey)) {
          throw StateError(
            'Exempted ayah $verseKey is not a recognized muqatta’at opening.',
          );
        }
      }
      validateArabicAyahText(
        text,
        label: 'Verse $verseKey',
        verseKey: verseKey,
      );

      final verseNumber = int.parse(verseKey.split(':').last);
      final charCount = text.length;

      db.execute(
        'INSERT INTO ayahs (id, surah_number, verse_number, verse_key, arabic_text, character_count) VALUES (?, ?, ?, ?, ?, ?)',
        [
          observedAyahCount + 1,
          chapterId,
          verseNumber,
          verseKey,
          text,
          charCount,
        ],
      );

      totalCharacterCount += charCount;
      observedAyahCount += 1;
    }
  }

  validateImportedChapterCounts(
    sourceChapterCounts: sourceChapterCounts,
    importedChapterCounts: importedChapterCounts,
  );
  validateCorpusTotals(
    observedAyahCount: observedAyahCount,
    expectedAyahCount: kExpectedAyahCount,
  );

  final importManifest = {
    'source': {
      'name': 'Quran.com API v4',
      'chapter_count_endpoint': kQuranChaptersEndpoint,
      'uthmani_text_endpoint': kQuranUthmaniEndpoint,
      'edition_identifier': kQuranEditionIdentifier,
      'edition_name': kQuranEditionName,
      'fetched_on': '2026-08-19',
    },
    'surah_count': kExpectedSurahCount,
    'ayah_count': kExpectedAyahCount,
    'chapter_counts': {
      for (final entry in sourceChapterCounts.entries)
        entry.key.toString(): entry.value,
    },
    'total_character_count': totalCharacterCount,
    'db_path': 'assets/quran.sqlite',
    'notes':
        'This manifest detects drift between runs; it does not validate the initial import. The initial import is validated by comparing the independent chapters endpoint to the imported ayah rows.',
  };

  final manifestFile = File(
    p.join(assetsDir.path, 'quran_import_manifest.json'),
  );
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(importManifest),
  );

  db.close();

  print('Muqatta’at exception list (${kMuqattaatExceptions.length}):');
  for (final key in kMuqattaatExceptions) {
    print('  - $key');
  }
  print('Total ayah count: $observedAyahCount');
  print('Total ayah count equals 6236: ${observedAyahCount == kExpectedAyahCount}');
  print(
    'Imported $observedAyahCount ayahs across ${importedChapterCounts.length} surahs.',
  );
  print('Total corpus character count: $totalCharacterCount');
  print('SQLite database written to ${dbFile.path}');
  print('Manifest written to ${manifestFile.path}');
}
