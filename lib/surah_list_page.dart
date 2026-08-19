import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
    required this.translation,
  });

  final int verseNumber;
  final String text;
  final String translation;
}

class QuranDataLoader {
  static Future<Map<String, dynamic>> _loadData() async {
    final jsonString = await rootBundle.loadString('assets/quran_reader_data.json');
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  static Future<String> loadAttribution() async {
    final decoded = await _loadData();
    return decoded['attribution'] as String? ??
        'Tanzil Project • English translation by Abdullah Yusuf Ali';
  }

  static Future<List<SurahSummary>> loadSurahs() async {
    final decoded = await _loadData();
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
    final decoded = await _loadData();
    final surahs = decoded['surahs'] as List<dynamic>;
    final target = surahs.firstWhere((surah) => surah['number'] == surahNumber);
    final ayahs = target['ayahs'] as List<dynamic>;

    return ayahs
        .map(
          (ayah) => AyahEntry(
            verseNumber: ayah['verse_number'] as int,
            text: ayah['text'] as String,
            translation: ayah['translation'] as String? ?? '',
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
  bool _showTranslations = true;

  @override
  void initState() {
    super.initState();
    _ayahsFuture = QuranDataLoader.loadAyahsForSurah(widget.surah.number);
  }

  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile.adaptive(
                  value: _showTranslations,
                  title: const Text('Show English translations'),
                  subtitle: const Text('Tanzil Project / Abdullah Yusuf Ali'),
                  onChanged: (value) {
                    setState(() {
                      _showTranslations = value;
                    });
                    Navigator.of(context).pop();
                  },
                ),
                const Divider(),
                const ListTile(
                  title: Text('Translation source'),
                  subtitle: Text('Tanzil Project • Abdullah Yusuf Ali'),
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('tanzil.net'),
                  subtitle: const Text('https://tanzil.net'),
                  onTap: () async {
                    final uri = Uri.parse('https://tanzil.net');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.nameSimple),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
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
              final showTranslation = _showTranslations && ayah.translation.trim().isNotEmpty;

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
                    if (showTranslation) ...[
                      const SizedBox(height: 12),
                      Text(
                        ayah.translation,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
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
