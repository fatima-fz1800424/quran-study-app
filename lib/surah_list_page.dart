import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SurahSummary {
  const SurahSummary({
    required this.number,
    required this.nameArabic,
    required this.nameSimple,
    required this.revelationPlace,
    required this.verseCount,
  });

  final int number;
  final String nameArabic;
  final String nameSimple;
  final String revelationPlace;
  final int verseCount;
}

class AyahEntry {
  const AyahEntry({
    required this.verseNumber,
    required this.text,
  });

  final int verseNumber;
  final String text;
}

class QuranDataLoader {
  static Future<List<SurahSummary>> loadSurahs() async {
    final jsonString = await rootBundle.loadString('assets/quran_reader_data.json');
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final surahs = decoded['surahs'] as List<dynamic>;

    return surahs
        .map(
          (surah) => SurahSummary(
            number: surah['number'] as int,
            nameArabic: surah['name_arabic'] as String,
            nameSimple: surah['name_simple'] as String,
            revelationPlace: surah['revelation_place'] as String,
            verseCount: surah['verse_count'] as int,
          ),
        )
        .toList();
  }

  static Future<List<AyahEntry>> loadAyahsForSurah(int surahNumber) async {
    final jsonString = await rootBundle.loadString('assets/quran_reader_data.json');
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final surahs = decoded['surahs'] as List<dynamic>;
    final target = surahs.firstWhere((surah) => surah['number'] == surahNumber);
    final ayahs = target['ayahs'] as List<dynamic>;

    return ayahs
        .map(
          (ayah) => AyahEntry(
            verseNumber: ayah['verse_number'] as int,
            text: ayah['text'] as String,
          ),
        )
        .toList();
  }
}

class SurahListPage extends StatefulWidget {
  const SurahListPage({super.key});

  @override
  State<SurahListPage> createState() => _SurahListPageState();
}

class _SurahListPageState extends State<SurahListPage> {
  late Future<List<SurahSummary>> _surahsFuture;

  @override
  void initState() {
    super.initState();
    _surahsFuture = QuranDataLoader.loadSurahs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Surah List')),
      body: FutureBuilder<List<SurahSummary>>(
        future: _surahsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final surahs = snapshot.data ?? const <SurahSummary>[];

          return ListView.separated(
            itemCount: surahs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final surah = surahs[index];
              return ListTile(
                title: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text('${surah.number}'),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            surah.nameArabic,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontFamily: 'AmiriQuran',
                              fontSize: 28,
                            ),
                          ),
                          Text(
                            '${surah.nameSimple} • ${surah.revelationPlace} • ${surah.verseCount} ayahs',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReaderPage(surah: surah),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({required this.surah, super.key});

  final SurahSummary surah;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late Future<List<AyahEntry>> _ayahsFuture;

  @override
  void initState() {
    super.initState();
    _ayahsFuture = QuranDataLoader.loadAyahsForSurah(widget.surah.number);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.surah.nameSimple)),
      body: FutureBuilder<List<AyahEntry>>(
        future: _ayahsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final ayahs = snapshot.data ?? const <AyahEntry>[];

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ayahs.length,
            itemBuilder: (context, index) {
              final ayah = ayahs[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${ayah.verseNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      ayah.text,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'AmiriQuran',
                        fontSize: 32,
                        height: 1.9,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
