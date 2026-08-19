import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart';

const String kQuranBackendBaseUrl = 'http://127.0.0.1:8123';

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
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const SurahListPage(),
      const AssistantPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) => setState(() => _selectedIndex = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Read'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Assistant'),
        ],
      ),
    );
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _surahsFuture = QuranDataLoader.loadSurahs();
    _lastReadFuture = QuranDataLoader.loadLastRead();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quran'),
      ),
      body: FutureBuilder<List<SurahSummary>>(
        future: _surahsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Something went wrong while loading the surah list.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }

          final allSurahs = snapshot.data ?? const <SurahSummary>[];
          final query = _searchController.text.trim().toLowerCase();
          final surahs = query.isEmpty
              ? allSurahs
              : allSurahs.where((surah) {
                  final haystack = '${surah.nameArabic} ${surah.nameSimple} ${surah.revelationPlace}'.toLowerCase();
                  return haystack.contains(query);
                }).toList();

          return FutureBuilder<LastReadState?>(
            future: _lastReadFuture,
            builder: (context, lastReadSnapshot) {
              final lastRead = lastReadSnapshot.data;

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search surah',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    if (lastRead != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            final resumeSurah = allSurahs.firstWhere(
                              (surah) => surah.number == lastRead.surahNumber,
                              orElse: () => allSurahs.first,
                            );
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReaderPage(
                                  surah: resumeSurah,
                                  initialAyah: lastRead.ayahNumber,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: theme.colorScheme.outline.withOpacity(0.45)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.play_arrow_rounded, color: theme.colorScheme.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Resume reading',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Surah ${allSurahs.firstWhere((s) => s.number == lastRead.surahNumber).nameSimple} • Ayah ${lastRead.ayahNumber}',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: surahs.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No surahs match your search.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: surahs.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: theme.dividerColor,
                              ),
                              itemBuilder: (context, index) {
                                final surah = surahs[index];
                                return InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ReaderPage(surah: surah),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 36,
                                          child: Text(
                                            '${surah.number}',
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                surah.nameArabic,
                                                textDirection: TextDirection.rtl,
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  fontFamily: 'AmiriQuran',
                                                  fontSize: 28,
                                                  height: 1.5,
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${surah.nameSimple} • ${surah.revelationPlace} • ${surah.verseCount} ayahs',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, child) {
            final settings = ref.read(appSettingsProvider.notifier);
            final currentSettings = ref.watch(appSettingsProvider);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    _SettingsSection(
                      title: 'Reading',
                      children: [
                        SwitchListTile.adaptive(
                          value: _showTranslations,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Show English translations'),
                          subtitle: const Text('Yusuf Ali translation'),
                          onChanged: (value) {
                            setState(() {
                              _showTranslations = value;
                            });
                          },
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Arabic font size',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text('${currentSettings.arabicFontSize.round()} px'),
                            ],
                          ),
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
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsSection(
                      title: 'Appearance',
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Theme',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              SegmentedButton<ThemeMode>(
                                segments: const [
                                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                                ],
                                selected: {currentSettings.themeMode},
                                onSelectionChanged: (value) {
                                  if (value.isNotEmpty) {
                                    settings.setThemeMode(value.first);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsSection(
                      title: 'Source',
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Translation source'),
                          subtitle: const Text('Tanzil Project • Abdullah Yusuf Ali'),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.link_rounded),
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.surah.nameSimple,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              widget.surah.nameArabic,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: 'AmiriQuran',
                fontSize: 22,
                height: 1.4,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This surah could not be loaded. Please try again.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }

          final ayahs = snapshot.data ?? const <AyahEntry>[];

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pendingScrollToAyah == null) {
              return;
            }
            final index = _pendingScrollToAyah! - 1;
            final key = _ayahKeys[index];
            if (key != null && key.currentContext != null) {
              Scrollable.ensureVisible(key.currentContext!, alignment: 0.45, duration: const Duration(milliseconds: 220));
            }
            _pendingScrollToAyah = null;
          });

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            itemCount: ayahs.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: theme.dividerColor,
            ),
            itemBuilder: (context, index) {
              final ayah = ayahs[index];
              final key = GlobalKey();
              _ayahKeys[index] = key;
              final isBookmarked = _bookmarks.contains('${widget.surah.number}:${ayah.verseNumber}');
              final showTranslation = _showTranslations && ayah.translation.trim().isNotEmpty;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Padding(
                    key: key,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${ayah.verseNumber}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: isBookmarked ? 'Remove bookmark' : 'Add bookmark',
                              icon: Icon(
                                isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                color: theme.colorScheme.primary,
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
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (showTranslation) ...[
                          const SizedBox(height: 12),
                          Text(
                            ayah.translation,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.6,
                              fontWeight: FontWeight.w400,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Permanent guardrail required by the brief: the assistant must always state
/// that it is a study aid, not a religious authority. It is intentionally not
/// dismissible and sits outside the scrolling area so it cannot be scrolled
/// away or buried in settings.
class _AssistantDisclaimer extends StatelessWidget {
  const _AssistantDisclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.tertiary.withOpacity(0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is a study tool drawing on the Yusuf Ali translation. '
              'It is not a substitute for a qualified scholar, and it does not '
              'give religious rulings. For rulings, ask a qualified scholar or '
              'your local imam.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _question;
  String? _answer;
  String? _error;
  List<String> _references = const [];

  Future<void> _submitQuestion() async {
    final question = _controller.text.trim();
    if (question.isEmpty) {
      return;
    }

    setState(() {
      _loading = true;
      _question = question;
      _answer = null;
      _error = null;
      _references = const [];
    });

    try {
      final response = await http.post(
        Uri.parse('$kQuranBackendBaseUrl/ask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': question}),
      );

      if (!mounted) {
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _answer = (decoded['answer'] as String?) ?? 'No answer returned.';
          _references = ((decoded['references'] as List<dynamic>?) ?? const [])
              .map((item) => item.toString())
              .toList();
        });
      } else {
        final decoded = jsonDecode(response.body);
        final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
        setState(() {
          _error = detail is String
              ? detail
              : 'The assistant could not answer that question.';
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to reach the backend at $kQuranBackendBaseUrl/ask. The backend needs to be running.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openReference(String reference) async {
    final parts = reference.split(':');
    if (parts.length != 2) {
      return;
    }

    final surahNumber = int.tryParse(parts[0]);
    final ayahNumber = int.tryParse(parts[1]);
    if (surahNumber == null || ayahNumber == null) {
      return;
    }

    final surahs = await QuranDataLoader.loadSurahs();
    if (!mounted) {
      return;
    }

    final match = surahs.firstWhere(
      (item) => item.number == surahNumber,
      orElse: () => surahs.first,
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          surah: match,
          initialAyah: ayahNumber,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              const _AssistantDisclaimer(),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    if (_question != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Question',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _question!,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    if (_question != null) const SizedBox(height: 16),
                    if (_answer != null || _error != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Answer',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error ?? _answer ?? '',
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (_references.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                'References',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _references
                                    .map(
                                      (ref) => ActionChip(
                                        label: Text(ref),
                                        onPressed: () => _openReference(ref),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      onSubmitted: (_) => _submitQuestion(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about a verse, topic, or theme',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: _submitQuestion,
                      icon: Icon(Icons.send_rounded, color: theme.colorScheme.onPrimary),
                      tooltip: 'Send question',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
