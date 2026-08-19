import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart';

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

class LastReadState {
  const LastReadState({required this.surahNumber, required this.ayahNumber});

  final int surahNumber;
  final int ayahNumber;
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

  static Future<LastReadState?> loadLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    final surah = prefs.getInt('last_read_surah');
    final ayah = prefs.getInt('last_read_ayah');
    if (surah == null || ayah == null) {
      return null;
    }
    return LastReadState(surahNumber: surah, ayahNumber: ayah);
  }

  static Future<void> saveLastRead(int surahNumber, int ayahNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_read_surah', surahNumber);
    await prefs.setInt('last_read_ayah', ayahNumber);
  }

  static Future<Set<String>> loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('quran_bookmarks') ?? []).toSet();
  }

  static Future<void> toggleBookmark(int surahNumber, int ayahNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = (prefs.getStringList('quran_bookmarks') ?? []).toSet();
    final key = '$surahNumber:$ayahNumber';
    if (bookmarks.contains(key)) {
      bookmarks.remove(key);
    } else {
      bookmarks.add(key);
    }
    await prefs.setStringList('quran_bookmarks', bookmarks.toList());
  }

  static Future<bool> isBookmarked(int surahNumber, int ayahNumber) async {
    final bookmarks = await loadBookmarks();
    return bookmarks.contains('$surahNumber:$ayahNumber');
  }
}

class SurahListPage extends ConsumerStatefulWidget {
  const SurahListPage({super.key});

  @override
  ConsumerState<SurahListPage> createState() => _SurahListPageState();
}

class _SurahListPageState extends ConsumerState<SurahListPage> {
  late Future<List<SurahSummary>> _surahsFuture;
  Future<LastReadState?>? _lastReadFuture;

  @override
  void initState() {
    super.initState();
    _surahsFuture = QuranDataLoader.loadSurahs();
    _lastReadFuture = QuranDataLoader.loadLastRead();
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

          return FutureBuilder<LastReadState?>(
            future: _lastReadFuture,
            builder: (context, lastReadSnapshot) {
              final lastRead = lastReadSnapshot.data;

              return ListView.separated(
                itemCount: surahs.length + (lastRead == null ? 0 : 1),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (lastRead != null && index == 0) {
                    final resumeSurah = surahs.firstWhere(
                      (surah) => surah.number == lastRead.surahNumber,
                      orElse: () => surahs.first,
                    );
                    return ListTile(
                      leading: const Icon(Icons.play_arrow_rounded),
                      title: const Text('Resume reading'),
                      subtitle: Text('Surah ${resumeSurah.nameSimple} • Ayah ${lastRead.ayahNumber}'),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReaderPage(
                              surah: resumeSurah,
                              initialAyah: lastRead.ayahNumber,
                            ),
                          ),
                        );
                      },
                    );
                  }

                  final itemIndex = lastRead == null ? index : index - 1;
                  final surah = surahs[itemIndex];
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
          );
        },
      ),
    );
  }
}

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({required this.surah, this.initialAyah, super.key});

  final SurahSummary surah;
  final int? initialAyah;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late Future<List<AyahEntry>> _ayahsFuture;
  bool _showTranslations = true;
  Set<String> _bookmarks = <String>{};
  final Map<int, GlobalKey> _ayahKeys = <int, GlobalKey>{};
  int? _pendingScrollToAyah;

  @override
  void initState() {
    super.initState();
    _pendingScrollToAyah = widget.initialAyah;
    _ayahsFuture = QuranDataLoader.loadAyahsForSurah(widget.surah.number);
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await QuranDataLoader.loadBookmarks();
    if (!mounted) {
      return;
    }
    setState(() {
      _bookmarks = bookmarks;
    });
  }

  Future<void> _toggleBookmark(int ayahNumber) async {
    await QuranDataLoader.toggleBookmark(widget.surah.number, ayahNumber);
    await _loadBookmarks();
    await QuranDataLoader.saveLastRead(widget.surah.number, ayahNumber);
  }

  Future<void> _saveLastRead(int ayahNumber) async {
    await QuranDataLoader.saveLastRead(widget.surah.number, ayahNumber);
  }

  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final settings = ref.read(appSettingsProvider.notifier);
            final currentSettings = ref.watch(appSettingsProvider);

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
                      },
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Theme'),
                      subtitle: Text(currentSettings.themeMode == ThemeMode.dark ? 'Dark' : 'Light'),
                      trailing: DropdownButton<ThemeMode>(
                        value: currentSettings.themeMode,
                        items: const [
                          DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                          DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                        ],
                        onChanged: (mode) {
                          if (mode == null) {
                            return;
                          }
                          settings.setThemeMode(mode);
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('Arabic font size'),
                      subtitle: Text('${currentSettings.arabicFontSize.round()} px'),
                    ),
                    Slider(
                      value: currentSettings.arabicFontSize,
                      min: kMinArabicFontSize,
                      max: kMaxArabicFontSize,
                      divisions: 28,
                      onChanged: (value) {
                        settings.setArabicFontSize(value);
                      },
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Bookmarked ayahs'),
                      subtitle: Text('${_bookmarks.where((entry) => entry.startsWith('${widget.surah.number}:')).length} saved'),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);

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

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pendingScrollToAyah == null) {
              return;
            }
            final index = _pendingScrollToAyah! - 1;
            final key = _ayahKeys[index];
            if (key != null && key.currentContext != null) {
              Scrollable.ensureVisible(key.currentContext!, alignment: 0.5);
            }
            _pendingScrollToAyah = null;
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ayahs.length,
            itemBuilder: (context, index) {
              final ayah = ayahs[index];
              final key = GlobalKey();
              _ayahKeys[index] = key;
              final isBookmarked = _bookmarks.contains('${widget.surah.number}:${ayah.verseNumber}');
              final showTranslation = _showTranslations && ayah.translation.trim().isNotEmpty;

              return Padding(
                key: key,
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '${ayah.verseNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: isBookmarked ? 'Remove bookmark' : 'Add bookmark',
                          icon: Icon(
                            isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          ),
                          onPressed: () async {
                            await _toggleBookmark(ayah.verseNumber);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      ayah.text,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'AmiriQuran',
                        fontSize: settings.arabicFontSize,
                        height: 1.9,
                      ),
                    ),
                    if (showTranslation) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          await _saveLastRead(ayah.verseNumber);
                        },
                        child: Text(
                          ayah.translation,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                          ),
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
