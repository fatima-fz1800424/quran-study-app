import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'about_page.dart';
import 'decoration.dart';
import 'main.dart';
import 'motion.dart';
import 'recitation.dart';
import 'voice.dart';

/// Where the study assistant's backend lives.
///
/// Supplied at compile time, because a web release build has no runtime
/// environment to read and no server-side config to fetch - the output is
/// static files. `String.fromEnvironment` is const-evaluated by the compiler,
/// so the value is fixed when the bundle is built:
///
///     flutter build web --dart-define=QURAN_BACKEND_BASE_URL=https://api.example.com
///
/// The default keeps `flutter run -d chrome` working with a backend started
/// from backend/README.md, which is the same port uvicorn falls back to.
/// No trailing slash: callers append paths beginning with one.
const String kQuranBackendBaseUrl = String.fromEnvironment(
  'QURAN_BACKEND_BASE_URL',
  defaultValue: 'http://127.0.0.1:8123',
);

const List<Map<String, String>> _verseOfDayPool = [
  {
    'surah': '2',
    'ayah': '155',
    'text':
        'And give good tidings to the patient, who, when disaster strikes them, say, "Indeed we belong to Allah, and indeed to Him we will return."',
    'reference': 'Al-Baqarah 2:155-156',
  },
  {
    'surah': '94',
    'ayah': '5',
    'text': 'Indeed, with hardship comes ease.',
    'reference': 'Ash-Sharh 94:5-6',
  },
  {
    'surah': '13',
    'ayah': '28',
    'text': 'Verily, in the remembrance of Allah do hearts find rest.',
    'reference': "Ar-Ra'd 13:28",
  },
  {
    'surah': '39',
    'ayah': '53',
    'text':
        'Say, "O My servants who have transgressed against themselves, do not despair of the mercy of Allah. Indeed, Allah forgives all sins."',
    'reference': 'Az-Zumar 39:53',
  },
  {
    'surah': '2',
    'ayah': '286',
    'text': 'Allah does not burden a soul beyond what it can bear.',
    'reference': 'Al-Baqarah 2:286',
  },
];


class SurahSummary {
  const SurahSummary({
    required this.number,
    required this.nameArabic,
    required this.nameSimple,
    required this.nameTransliterated,
    required this.revelationPlace,
    required this.verseCount,
    this.bismillah,
  });

  final int number;
  final String nameArabic;
  final String nameSimple;

  /// The surah's transliterated Arabic name, e.g. "Al-Baqara". Searchable, so
  /// looking for "baqara" works as well as looking for the English meaning.
  final String nameTransliterated;

  final String revelationPlace;
  final int verseCount;

  /// The surah's opening Bismillah, exactly as the corpus stores it, or null
  /// for al-Fatihah where it is verse 1 and at-Tawbah which has none. Rendered
  /// from the verified corpus, never typed out.
  final String? bismillah;
}

/// Fold text into a form the surah search can compare.
///
/// Separators are dropped and runs of the same character collapsed, because
/// Tanzil's transliterations double long vowels - "Al-Faatiha", "Al-Ikhlaas",
/// "An-Naas" - while people type "fatiha", "ikhlas", "nas". A plain substring
/// match fails on all three. Both the query and the candidate go through this,
/// so the comparison stays symmetric.
String normaliseForSearch(String value) {
  final stripped = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9؀-ۿ]'), '');
  final buffer = StringBuffer();
  for (var i = 0; i < stripped.length; i++) {
    if (i == 0 || stripped[i] != stripped[i - 1]) {
      buffer.write(stripped[i]);
    }
  }
  return buffer.toString();
}

/// Whether [surah] should be shown for a free-text [query].
///
/// Matches on the number, the Arabic name, the English meaning, the
/// transliteration and the revelation place.
bool surahMatchesQuery(SurahSummary surah, String query) {
  final needle = normaliseForSearch(query);
  if (needle.isEmpty) {
    return true;
  }
  final haystack = normaliseForSearch(
    '${surah.number} ${surah.nameArabic} ${surah.nameSimple} '
    '${surah.nameTransliterated} ${surah.revelationPlace}',
  );
  return haystack.contains(needle);
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
  // The reader payload is ~2.9MB of JSON and was previously re-read and
  // re-decoded on every call - once per surah opened, and again for every
  // citation followed. Holding the decoded map costs memory but makes opening a
  // verse instant, which navigation from a citation depends on.
  static Map<String, dynamic>? _decoded;
  static List<SurahSummary>? _surahs;

  /// The surah list if it has already been loaded, otherwise null. Lets callers
  /// that must not wait - navigating to a cited verse - resolve a surah without
  /// an await.
  static List<SurahSummary>? get cachedSurahs => _surahs;

  /// Install a corpus payload directly, bypassing the asset bundle.
  ///
  /// Widget tests cannot load the real asset: `rootBundle` needs real async,
  /// which the fake-async test zone does not run, so anything that awaits it
  /// hangs. Seeding the cache lets the reader be exercised for real in tests -
  /// including scrolling, which was previously impossible to verify.
  @visibleForTesting
  static void seedCorpusForTests(Map<String, dynamic> data) {
    _decoded = data;
    _surahs = null;
  }

  static Future<Map<String, dynamic>> _loadData() async {
    final cached = _decoded;
    if (cached != null) {
      return cached;
    }
    final jsonString = await rootBundle.loadString(
      'assets/quran_reader_data.json',
    );
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    _decoded = decoded;
    return decoded;
  }

  static Future<List<SurahSummary>> loadSurahs() async {
    final cached = _surahs;
    if (cached != null) {
      return cached;
    }

    final decoded = await _loadData();
    final surahs = decoded['surahs'] as List<dynamic>;

    final loaded = surahs
        .map(
          (surah) => SurahSummary(
            number: surah['number'] as int,
            nameArabic: surah['name_arabic'] as String,
            nameSimple: surah['name_simple'] as String,
            nameTransliterated: surah['name_transliterated'] as String? ?? '',
            revelationPlace: surah['revelation_place'] as String,
            verseCount: surah['verse_count'] as int,
            bismillah: surah['bismillah'] as String?,
          ),
        )
        .toList();
    _surahs = loaded;
    return loaded;
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

/// Tabs in [MainShell]. Kept as named constants so cross-tab navigation reads
/// as intent rather than as an index.
const int kReadTabIndex = 0;
const int kAssistantTabIndex = 1;

/// The verse a citation asked the reader to open.
class ReaderTarget {
  const ReaderTarget({required this.surahNumber, required this.ayahNumber});

  final int surahNumber;
  final int ayahNumber;

  String get reference => '$surahNumber:$ayahNumber';
}

/// Parse a `surah:verse` reference, or null if it is not one.
///
/// Bounds are checked against the corpus - 114 surahs, longest is 286 verses -
/// so a stray number in model output cannot become a navigation target.
ReaderTarget? parseReference(String reference) {
  final parts = reference.trim().split(':');
  if (parts.length != 2) {
    return null;
  }
  final surahNumber = int.tryParse(parts[0]);
  final ayahNumber = int.tryParse(parts[1]);
  if (surahNumber == null || ayahNumber == null) {
    return null;
  }
  if (surahNumber < 1 ||
      surahNumber > 114 ||
      ayahNumber < 1 ||
      ayahNumber > 286) {
    return null;
  }
  return ReaderTarget(surahNumber: surahNumber, ayahNumber: ayahNumber);
}

/// Which tab [MainShell] is showing. Held outside the shell so a tap on a
/// citation in the assistant can move the user to the reader.
final selectedTabProvider = StateProvider<int>((ref) => kReadTabIndex);

/// A pending request to open a verse in the reader. Set by whoever wants to
/// navigate; cleared by the reader tab once it has handled it.
final readerTargetProvider = StateProvider<ReaderTarget?>((ref) => null);

/// The HTTP client the assistant talks to the backend with. Overridden in tests
/// so the assistant's handling of a reply can be exercised without a backend.
final httpClientProvider = Provider<http.Client>((ref) => http.Client());

/// The last reading position, held in state rather than read once into a Future.
///
/// It has to be state: the surah list is never disposed - it lives in the
/// shell's IndexedStack - so anything loaded in its initState is loaded exactly
/// once per app run. A one-shot Future here meant the resume row kept showing
/// whatever position happened to be stored at launch, no matter how much
/// reading happened afterwards.
class LastReadNotifier extends StateNotifier<LastReadState?> {
  LastReadNotifier() : super(null) {
    _load();
  }

  /// True once a position has been recorded in this session.
  ///
  /// The initial load is asynchronous, so it can finish after the user has
  /// already opened a surah. Without this flag it would then overwrite that
  /// fresh position with the older stored one - and the reader saves on open,
  /// so the race is the common case on a fast launch, not a rare one.
  bool _recordedThisSession = false;

  Future<void> _load() async {
    final stored = await QuranDataLoader.loadLastRead();
    if (_recordedThisSession || !mounted) {
      return;
    }
    state = stored;
  }

  /// Record a position, whether or not this notifier is still alive.
  ///
  /// The reader flushes its last position from `deactivate`, off a microtask,
  /// so this can land after the provider has been disposed - on app teardown
  /// it always does. Touching `state` then throws, and because the throw is
  /// asynchronous it surfaces against whatever runs next rather than here,
  /// which is what made the test suite order-dependent. The write still has to
  /// happen: flushing the final position is the entire point of that call, and
  /// it is the stored value, not the in-memory one, that resume reads.
  Future<void> save(int surahNumber, int ayahNumber) async {
    if (!mounted) {
      await QuranDataLoader.saveLastRead(surahNumber, ayahNumber);
      return;
    }

    final current = state;
    if (current != null &&
        current.surahNumber == surahNumber &&
        current.ayahNumber == ayahNumber) {
      return;
    }
    _recordedThisSession = true;
    // State first so the UI updates in this frame; the write follows.
    state = LastReadState(surahNumber: surahNumber, ayahNumber: ayahNumber);
    await QuranDataLoader.saveLastRead(surahNumber, ayahNumber);
  }
}

final lastReadProvider =
    StateNotifierProvider<LastReadNotifier, LastReadState?>(
      (ref) => LastReadNotifier(),
    );

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedTabProvider);

    final pages = <Widget>[const SurahListPage(), const AssistantPage()];

    return Scaffold(
      // A plain IndexedStack, and deliberately so. Wrapping it in an
      // AnimatedSwitcher keyed on the index cost three things and bought a
      // 240ms crossfade: the key replaced the whole subtree on every switch,
      // so both tabs were rebuilt from scratch and a half-typed question or a
      // scroll position was thrown away; both copies were briefly in the tree
      // at once, so there were two of every control; and the arriving tab was
      // faded up from zero opacity, and a render object at zero opacity
      // contributes no semantics, so a screen reader saw an empty screen for
      // the length of the fade. Arrival motion belongs inside each page, where
      // it cannot take the page's state or its accessibility with it.
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) =>
            ref.read(selectedTabProvider.notifier).state = value,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Read',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Assistant',
          ),
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
  final TextEditingController _searchController = TextEditingController();

  // Select one stable verse for each calendar day. Using days since the Unix
  // epoch avoids repeating the same verse on the same day of every month.
  final int _verseOfDayIndex = DateTime.now()
          .difference(DateTime(1970, 1, 1))
          .inDays %
      _verseOfDayPool.length;
  
  @override
  void initState() {
    super.initState();
    _surahsFuture = QuranDataLoader.loadSurahs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Open a verse that something outside this tab asked for, without waiting on
  /// a rebuild or a spinner. The surah list is normally already cached by the
  /// time a citation can be tapped, so the common path does not await at all.
  void _openReaderTarget(ReaderTarget target) {
    final cached = QuranDataLoader.cachedSurahs;
    if (cached != null) {
      _pushReader(cached, target);
      return;
    }
    // Cold start only: the list has not finished loading yet.
    QuranDataLoader.loadSurahs().then((surahs) {
      if (mounted) {
        _pushReader(surahs, target);
      }
    });
  }

  void _pushReader(List<SurahSummary> surahs, ReaderTarget target) {
    final match = surahs.where((item) => item.number == target.surahNumber);
    if (match.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          surah: match.first,
          initialAyah: target.ayahNumber,
          highlightInitialAyah: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Watched, not loaded once: this rebuilds whenever the reader records a new
    // position, which is what keeps the resume row current.
    // Consume any pending request to open a verse. Cleared immediately so a
    // later rebuild cannot re-open the same verse.
    ref.listen<ReaderTarget?>(readerTargetProvider, (previous, next) {
      if (next == null) {
        return;
      }
      ref.read(readerTargetProvider.notifier).state = null;
      _openReaderTarget(next);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Quran')),
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
          final query = _searchController.text.trim();
          final surahs = query.isEmpty
              ? allSurahs
              : allSurahs
                    .where((surah) => surahMatchesQuery(surah, query))
                    .toList();

          return Builder(
            builder: (context) {
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
                    Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: EntranceFade(
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F6E56),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -25,
            right: -15,
            child: Opacity(
              opacity: 0.15,
              child: Icon(
                Icons.menu_book_rounded,
                size: 110,
                color: Colors.white,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.25),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Verse of the day',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '"${_verseOfDayPool[_verseOfDayIndex]['text']}"',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _verseOfDayPool[_verseOfDayIndex]['reference']!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          final verse = _verseOfDayPool[_verseOfDayIndex];
                          SharePlus.instance.share(
                            ShareParams(
                              text:
                                  '"${verse['text']}"\n\n— ${verse['reference']}\n\nShared from the Quran Study App',
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.25),
                          ),
                          child: const Icon(
                            Icons.share_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        backgroundColor: Colors.white.withOpacity(0.25),
                        side: BorderSide.none,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Read in context',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ],
                        ),
                        onPressed: () {
                          final verse = _verseOfDayPool[_verseOfDayIndex];
                          final surahNumber = int.parse(verse['surah']!);
                          final ayahNumber = int.parse(verse['ayah']!);
                          final targetSurah = allSurahs.firstWhere(
                            (surah) => surah.number == surahNumber,
                            orElse: () => allSurahs.first,
                          );
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReaderPage(
                                surah: targetSurah,
                                initialAyah: ayahNumber,
                                highlightInitialAyah: true,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  ),
),


                    Expanded(
                      child: surahs.isEmpty
                          ? const Center(
                              child: Text('No surahs found.'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: surahs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final surah = surahs[index];
                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          theme.colorScheme.primaryContainer,
                                      child: Text('${surah.number}'),
                                    ),
                                    title: Text(
                                      surah.nameSimple,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${surah.nameTransliterated} • '
                                      '${surah.verseCount} ayahs • '
                                      '${surah.revelationPlace}',
                                    ),
                                    trailing: Text(
                                      surah.nameArabic,
                                      textDirection: TextDirection.rtl,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    onTap: () {
                                      ref
                                          .read(lastReadProvider.notifier)
                                          .save(surah.number, 1);
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ReaderPage(
                                            surah: surah,
                                            initialAyah: 1,
                                          ),
                                        ),
                                      );
                                    },
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
  const ReaderPage({
    required this.surah,
    this.initialAyah,
    this.highlightInitialAyah = false,
    super.key,
  });

  final SurahSummary surah;
  final int? initialAyah;

  /// Briefly tint [initialAyah] on arrival. Used when the user was sent here
  /// from somewhere else - a citation in the assistant - so that it is obvious
  /// which verse they landed on among its neighbours.
  final bool highlightInitialAyah;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with SingleTickerProviderStateMixin {
  late Future<List<AyahEntry>> _ayahsFuture;
  bool _showTranslations = true;
  Set<String> _bookmarks = <String>{};
  final Map<int, GlobalKey> _ayahKeys = <int, GlobalKey>{};
  final Map<int, int> _indexToVerse = <int, int>{};
  final GlobalKey _listKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final int _verseOfDayIndex = DateTime.now().day % _verseOfDayPool.length;
  int? _pendingScrollToAyah;
  int _scrollAttempts = 0;
  int? _highlightedAyah;
  Timer? _highlightTimer;
  Timer? _scrollSettleTimer;

  /// The ayah currently being recited, or null when nothing is playing. Drives
  /// the playing highlight and the auto-scroll that follows the recitation.
  int? _playingVerse;
  bool _audioBusy = false;
  String? _audioError;
  bool _scrollMovedDuringCooldown = false;
  bool _observationScheduled = false;
  int? _observedVerse;
  late final LastReadNotifier _lastRead;
  late final RecitationService _recitation;
  late final FullSurahService _fullSurah;

  /// True while the whole-surah player is running. Distinct from
  /// [_playingVerse]: this mode has no verse to track.
  bool _fullSurahPlaying = false;

  /// Drives the play/pause morph. Held here rather than derived from state so
  /// the icon animates between shapes instead of being swapped out.
  late final AnimationController _playPauseController;
  late final Animation<double> _playPauseAnimation;

  static const Duration _highlightHold = Duration(milliseconds: 1600);

  @override
  void initState() {
    super.initState();
    // Captured here so they stay usable during teardown, when `ref` is not.
    _lastRead = ref.read(lastReadProvider.notifier);
    _recitation = ref.read(recitationServiceProvider);
    _fullSurah = ref.read(fullSurahServiceProvider);
    _playPauseController = AnimationController(
      vsync: this,
      duration: Motion.quick,
    );
    _playPauseAnimation = CurvedAnimation(
      parent: _playPauseController,
      curve: Motion.curve,
    );
    _pendingScrollToAyah = widget.initialAyah;
    if (widget.highlightInitialAyah) {
      _highlightedAyah = widget.initialAyah;
      _highlightTimer = Timer(_highlightHold, () {
        if (mounted) {
          setState(() => _highlightedAyah = null);
        }
      });
    }
    _scrollController.addListener(_handleScroll);
    _ayahsFuture = QuranDataLoader.loadAyahsForSurah(widget.surah.number);
    _loadBookmarks();
    // Opening a surah is itself a read position, recorded so that resume works
    // even if the reader is closed again without scrolling or bookmarking.
    // Deferred by a frame because this writes to a provider, and Riverpod
    // rightly refuses provider writes from initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _saveLastRead(widget.initialAyah ?? 1);
      }
    });
  }

  @override
  void dispose() {
    // Leaving the reader must not leave audio playing behind it. Uses the
    // captured service: `ref` is already dead by dispose.
    _recitation.stop();
    _fullSurah.stop();
    _playPauseController.dispose();
    _highlightTimer?.cancel();
    _scrollSettleTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
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
    await _saveLastRead(ayahNumber);
  }

  Future<void> _saveLastRead(int ayahNumber) async {
    // The notifier dedupes on the surah and verse together, so it is safe to
    // call this freely, and the surah list sees the change immediately.
    await _lastRead.save(widget.surah.number, ayahNumber);
  }

  @override
  void deactivate() {
    // Last chance to record where the reader actually stopped. Without this,
    // closing the page within the throttle window discarded the final position.
    // Uses the last observed verse rather than measuring now: render objects
    // are already detached by this point.
    final verse = _observedVerse;
    if (verse != null) {
      final surahNumber = widget.surah.number;
      final notifier = _lastRead;
      // Deferred off the lifecycle: this runs while the tree is being torn
      // down, and Riverpod refuses provider writes during a build.
      Future.microtask(() => notifier.save(surahNumber, verse));
    }
    super.deactivate();
  }

  static const Duration _scrollSettle = Duration(milliseconds: 250);

  /// Record the read position while scrolling, throttled rather than debounced.
  ///
  /// The first scroll event records straight away, then at most one write per
  /// [_scrollSettle] for as long as scrolling continues. A pure trailing
  /// debounce looked tidier but lost the position whenever the reader closed
  /// before the timer fired - which is precisely what scrolling and then
  /// tapping back does, so the recorded verse stayed at whatever was saved when
  /// the surah opened.
  void _handleScroll() {
    // Measure after the frame, not here. A scroll notification arrives before
    // layout has run, so the render boxes still describe the previous frame and
    // every reading lags a step behind. Coalesced to one measurement per frame.
    if (_observationScheduled) {
      return;
    }
    _observationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _observeAndPersist());
  }

  /// Note where the reader is, and write it if the throttle allows.
  ///
  /// The observation is kept even when the write is throttled, so teardown has
  /// a current position to flush without measuring anything itself.
  void _observeAndPersist() {
    _observationScheduled = false;
    if (!mounted) {
      return;
    }
    final verse = _topmostVisibleVerse();
    if (verse == null) {
      return;
    }
    _observedVerse = verse;

    if (_scrollSettleTimer != null) {
      _scrollMovedDuringCooldown = true;
      return;
    }
    _saveLastRead(verse);
    _scrollSettleTimer = Timer(_scrollSettle, _afterScrollCooldown);
  }

  void _afterScrollCooldown() {
    _scrollSettleTimer = null;
    if (!_scrollMovedDuringCooldown || !mounted) {
      return;
    }
    _scrollMovedDuringCooldown = false;
    _persistObservedVerse();
    _scrollSettleTimer = Timer(_scrollSettle, _afterScrollCooldown);
  }

  void _persistObservedVerse() {
    final verse = _observedVerse;
    if (verse != null && mounted) {
      _saveLastRead(verse);
    }
  }

  /// Start reciting from [verse], or stop if that verse is already playing.
  ///
  /// Playback always goes through one queued player rather than one player per
  /// ayah: browsers gate audible playback on a user gesture, and this tap is
  /// that gesture for the whole queue.
  Future<void> _toggleRecitation(int verse, List<AyahEntry> ayahs) async {
    final service = _recitation;

    if (_playingVerse == verse) {
      await service.stop();
      if (mounted) {
        setState(() => _playingVerse = null);
      }
      return;
    }

    setState(() {
      _audioBusy = true;
      _audioError = null;
    });

    try {
      var reciter = ref.read(reciterProvider);
      if (reciter == null) {
        // Cold start: wait for the list rather than refusing the tap.
        try {
          await ref.read(recitersProvider.future);
        } catch (_) {
          // Handled by the null check below.
        }
        if (!mounted) {
          return;
        }
        reciter = ref.read(reciterProvider);
      }
      // Promoted to a final local so it stays non-null through the closures
      // below.
      final selected = reciter;
      if (selected == null) {
        setState(
          () => _audioError =
              'No reciter available. Recitation needs a connection.',
        );
        return;
      }
      final source = await service.resolveSource(selected);
      if (!mounted) {
        return;
      }
      if (source == null) {
        setState(
          () => _audioError =
              'Could not find audio for ${selected.label}. '
              'Try another reciter.',
        );
        return;
      }

      await service.play(
        source: source,
        surah: widget.surah.number,
        verses: ayahs.map((ayah) => ayah.verseNumber).toList(),
        startVerse: verse,
        onVerse: (playing) {
          if (!mounted) {
            return;
          }
          setState(() => _playingVerse = playing);
          // Recitation drives the view, so the reader does not have to.
          _scrollToVerse(playing);
          // Where the user is listening is where they are reading.
          _saveLastRead(playing);
        },
        onDone: () {
          if (mounted) {
            setState(() => _playingVerse = null);
          }
        },
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _audioError =
              'Recitation could not be played. Check your connection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _audioBusy = false);
      }
    }
  }

  /// Start, pause or resume whole-surah playback.
  ///
  /// No verse tracking here on purpose: mp3quran publishes one file per surah
  /// with no ayah boundaries, so there is nothing to highlight or scroll to.
  /// Pretending otherwise would be a worse experience than not offering it.
  Future<void> _toggleFullSurah() async {
    if (_fullSurahPlaying) {
      await _fullSurah.pause();
      if (mounted) {
        setState(() => _fullSurahPlaying = false);
        _playPauseController.reverse();
      }
      return;
    }

    setState(() {
      _audioBusy = true;
      _audioError = null;
    });

    try {
      var recitation = ref.read(surahRecitationProvider);
      if (recitation == null) {
        try {
          await ref.read(fullSurahRecitationsProvider.future);
        } catch (_) {
          // Handled by the null check below.
        }
        if (!mounted) {
          return;
        }
        recitation = ref.read(surahRecitationProvider);
      }

      final selected = recitation;
      if (selected == null) {
        setState(
          () => _audioError =
              'No reciter available. Recitation needs a connection.',
        );
        return;
      }
      // Many sets are incomplete, so this is checked before playing rather
      // than surfaced as a failed request.
      if (!selected.hasSurah(widget.surah.number)) {
        setState(
          () => _audioError =
              '${selected.reciterName} does not have '
              '${widget.surah.nameSimple}. Try another reciter.',
        );
        return;
      }

      // Only one player at a time.
      await _recitation.stop();
      if (mounted) {
        setState(() => _playingVerse = null);
      }

      await _fullSurah.play(
        selected.urlFor(widget.surah.number),
        onDone: () {
          if (mounted) {
            setState(() => _fullSurahPlaying = false);
            _playPauseController.reverse();
          }
        },
      );
      if (mounted) {
        setState(() => _fullSurahPlaying = true);
        _playPauseController.forward();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _audioError =
              'Recitation could not be played. Check your connection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _audioBusy = false);
      }
    }
  }

  /// Bring [verse] into view, used to follow the recitation.
  /// Bring [verse] into view, but only when it is not already there.
  ///
  /// The unconditional version was a trap. `ensureVisible` always animates, and
  /// Flutter's `Scrollable` ignores pointers for as long as a scroll animation
  /// is in flight - deliberately, so that nobody taps a moving list. So tapping
  /// play on a verse already on screen nudged it to the 30% line and made every
  /// control in the reader inert for 300ms, including the stop button that had
  /// just appeared under the finger that started it. Scrolling to something the
  /// reader can already see buys nothing and costs that.
  void _scrollToVerse(int verse) {
    final index = _indexToVerse.entries
        .firstWhere(
          (entry) => entry.value == verse,
          orElse: () => const MapEntry(-1, -1),
        )
        .key;
    if (index < 0) {
      return;
    }
    final context = _ayahKeys[index]?.currentContext;
    if (context == null) {
      return;
    }
    if (_isComfortablyVisible(context)) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 300),
    );
  }

  /// Whether enough of [target] is on screen that moving the list would only
  /// disturb the reader.
  ///
  /// "Enough" is the whole verse, or 60% of the viewport for a verse too long
  /// to fit in it at once - otherwise a single long ayah could never satisfy
  /// the test and would be re-scrolled on every callback.
  bool _isComfortablyVisible(BuildContext target) {
    final box = target.findRenderObject() as RenderBox?;
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null ||
        listBox == null ||
        !box.attached ||
        !listBox.attached ||
        !box.hasSize ||
        !listBox.hasSize) {
      // Nothing measurable, so let ensureVisible decide.
      return false;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final viewportTop = listBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + listBox.size.height;
    final visible =
        math.min(top + box.size.height, viewportBottom) -
        math.max(top, viewportTop);
    final enough = math.min(box.size.height, listBox.size.height * 0.6);
    return visible >= enough;
  }

  /// The verse number of the topmost ayah still visible in the viewport, or
  /// null while the list has not been laid out yet.
  int? _topmostVisibleVerse() {
    final listContext = _listKey.currentContext;
    if (listContext == null) {
      return null;
    }
    final listBox = listContext.findRenderObject() as RenderBox?;
    if (listBox == null || !listBox.attached || !listBox.hasSize) {
      return null;
    }
    final viewportTop = listBox.localToGlobal(Offset.zero).dy;

    int? topmostIndex;
    for (final entry in _ayahKeys.entries) {
      final ayahContext = entry.value.currentContext;
      if (ayahContext == null) {
        continue;
      }
      final box = ayahContext.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) {
        continue;
      }
      if (box.localToGlobal(Offset.zero).dy + box.size.height <= viewportTop) {
        continue; // scrolled fully past the top of the viewport
      }
      if (topmostIndex == null || entry.key < topmostIndex) {
        topmostIndex = entry.key;
      }
    }

    return topmostIndex == null ? null : _indexToVerse[topmostIndex];
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
              child: SingleChildScrollView(
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
                              Text(
                                '${currentSettings.arabicFontSize.round()} px',
                              ),
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
                      title: 'Recitation',
                      children: [
                        Consumer(
                          builder: (context, ref, child) {
                            final mode = ref.watch(recitationModeProvider);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SegmentedButton<RecitationMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: RecitationMode.verseByVerse,
                                      label: Text('Verse by verse'),
                                    ),
                                    ButtonSegment(
                                      value: RecitationMode.fullSurah,
                                      label: Text('Full surah'),
                                    ),
                                  ],
                                  selected: {mode},
                                  onSelectionChanged: (selection) {
                                    ref
                                        .read(recitationModeProvider.notifier)
                                        .select(selection.first);
                                  },
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  mode == RecitationMode.verseByVerse
                                      ? 'Plays one ayah at a time, highlighting '
                                            'and scrolling as it goes. Nine reciters.'
                                      : 'Plays the surah as one recording. Many '
                                            'more reciters, but no verse tracking - '
                                            'these files have no ayah boundaries.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            );
                          },
                        ),
                        Consumer(
                          builder: (context, ref, child) {
                            if (ref.watch(recitationModeProvider) ==
                                RecitationMode.fullSurah) {
                              return const _FullSurahReciterPicker();
                            }
                            final selected = ref.watch(reciterProvider);
                            final available = ref.watch(recitersProvider);
                            return available.when(
                              loading: () => const ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Loading reciters...'),
                              ),
                              error: (error, _) => const ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Reciters unavailable'),
                                subtitle: Text(
                                  'Recitation needs a connection. Reading does not.',
                                ),
                              ),
                              data: (reciters) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Reciter'),
                                subtitle: Text(
                                  selected?.label ?? 'Choose a reciter',
                                ),
                                trailing: DropdownButton<Reciter>(
                                  value: selected,
                                  underline: const SizedBox.shrink(),
                                  items: [
                                    for (final reciter in reciters)
                                      DropdownMenuItem(
                                        value: reciter,
                                        child: Text(reciter.label),
                                      ),
                                  ],
                                  onChanged: (reciter) {
                                    if (reciter != null) {
                                      ref
                                          .read(reciterProvider.notifier)
                                          .select(reciter);
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
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
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    label: Text('Light'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    label: Text('Dark'),
                                  ),
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
                          subtitle: const Text(
                            'Tanzil Project • Abdullah Yusuf Ali',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.link_rounded),
                          title: const Text('tanzil.net'),
                          subtitle: const Text('https://tanzil.net'),
                          onTap: () async {
                            final uri = Uri.parse('https://tanzil.net');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsSection(
                      title: 'About',
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.info_outline_rounded),
                          title: const Text('About this app'),
                          subtitle: const Text(
                            'Credits, licences, and what the assistant will '
                            'not do',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            // The sheet closes first, and the push uses the
                            // reader's context rather than the sheet's: the
                            // sheet's is defunct the moment it is popped.
                            Navigator.of(sheetContext).pop();
                            Navigator.of(this.context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const AboutPage(),
                              ),
                            );
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
    final mode = ref.watch(recitationModeProvider);
    // Watched here, not only in the settings sheet: the provider is lazy, and
    // loading it is what restores the stored reciter and picks a default. Until
    // this ran, the first tap on play could only fail.
    if (mode == RecitationMode.verseByVerse) {
      ref.watch(recitersProvider);
    } else {
      ref.watch(fullSurahRecitationsProvider);
    }

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
            Text(widget.surah.nameSimple, style: theme.textTheme.titleMedium),
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
          if (mode == RecitationMode.fullSurah)
            IconButton(
              icon: AnimatedIcon(
                icon: AnimatedIcons.play_pause,
                progress: _playPauseAnimation,
              ),
              tooltip: _fullSurahPlaying
                  ? 'Pause recitation'
                  : 'Play the whole surah',
              onPressed: _audioBusy ? null : _toggleFullSurah,
            ),
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
          final audioError = _audioError;
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (_pendingScrollToAyah == null) {
    return;
  }
  final index = _pendingScrollToAyah!;
  final key = _ayahKeys[index];
  if (key != null && key.currentContext != null) {
    Scrollable.ensureVisible(
      key.currentContext!,
      alignment: 0.45,
      duration: const Duration(milliseconds: 220),
    );
    _pendingScrollToAyah = null;
    _scrollAttempts = 0;
    return;
  }

  if (!_scrollController.hasClients) {
    return;
  }

  // Give up after a handful of tries rather than looping forever.
  if (_scrollAttempts >= 10) {
    _pendingScrollToAyah = null;
    _scrollAttempts = 0;
    return;
  }
  _scrollAttempts++;

  // Use the closest already-built verse to estimate real item height,
  // instead of a fixed guess that breaks on surahs with long verses.
  MapEntry<int, GlobalKey>? nearest;
  for (final entry in _ayahKeys.entries) {
    if (entry.value.currentContext == null) continue;
    if (nearest == null ||
        (entry.key - index).abs() < (nearest.key - index).abs()) {
      nearest = entry;
    }
  }

  double estimatedOffset;
  if (nearest != null) {
    final box = nearest.value.currentContext!.findRenderObject() as RenderBox;
    final itemHeight = box.size.height + 10; // + separator
    final nearestGlobalY = box.localToGlobal(Offset.zero).dy;
    final nearestOffset = _scrollController.offset + nearestGlobalY;
    estimatedOffset = nearestOffset + (index - nearest.key) * itemHeight;
  } else {
    // No items built yet at all: fall back to a rough constant guess.
    estimatedOffset = index * 260.0;
  }

  estimatedOffset = estimatedOffset.clamp(
    0.0,
    _scrollController.position.maxScrollExtent,
  );
  _scrollController.jumpTo(estimatedOffset);
  setState(() {});
});
          if (audioError != null) {
            // Reported inline rather than as a snackbar: the reader may be
            // scrolled anywhere, and a transient toast is easy to miss.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final messenger = ScaffoldMessenger.maybeOf(context);
              messenger?.hideCurrentSnackBar();
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(audioError),
                  action: SnackBarAction(
                    label: 'Choose reciter',
                    onPressed: _showSettingsSheet,
                  ),
                ),
              );
              setState(() => _audioError = null);
            });
          }

          return ListView.separated(
            key: _listKey,
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            // One extra item: the gradient header at index 0. It scrolls away
            // with the content rather than staying fixed above the verses.
            itemCount: ayahs.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: EntranceFade(
                      child: _SurahHeaderCard(surah: widget.surah),
                    ),
                  ),
                );
              }
              final ayah = ayahs[index - 1];
              // Keys must be stable across rebuilds: they anchor both the
              // scroll-to-ayah jump and the read-position tracking.
              final key = _ayahKeys.putIfAbsent(index, () => GlobalKey());
              // Keyed by list index, which is one ahead of the verse index now
              // that the header occupies position zero.
              _indexToVerse[index] = ayah.verseNumber;
              final isBookmarked = _bookmarks.contains(
                '${widget.surah.number}:${ayah.verseNumber}',
              );
              final showTranslation =
                  _showTranslations && ayah.translation.trim().isNotEmpty;
              final isHighlighted = _highlightedAyah == ayah.verseNumber;
              final isReciting = _playingVerse == ayah.verseNumber;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: EntranceFade(
                    child: AnimatedContainer(
                    key: key,
                    duration: Motion.duration(context, Motion.normal),
                    curve: Motion.curve,
                    decoration: BoxDecoration(
                      // The card itself stays the plain surface colour: the
                      // Arabic sits on it, so nothing tinted goes behind the
                      // text. State is carried by the strip and the shadow.
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: isReciting
                          ? Elevation.raised(
                              theme.brightness,
                              theme.colorScheme.primary,
                            )
                          : Elevation.resting(theme.brightness),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tinted action strip. All the colour for this row
                        // lives here, above the verse rather than behind it.
                        AnimatedContainer(
                          duration: Motion.duration(context, Motion.normal),
                          curve: Motion.curve,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          color: isReciting
                              ? theme.colorScheme.primary.withOpacity(0.16)
                              : isHighlighted
                              ? theme.colorScheme.tertiary.withOpacity(0.14)
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary.withOpacity(
                                  theme.brightness == Brightness.light
                                      ? 0.12
                                      : 0.22,
                                ),
                              ),
                              child: Text(
                                '${ayah.verseNumber}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (mode == RecitationMode.verseByVerse)
                              IconButton(
                                tooltip: isReciting
                                    ? 'Stop reciting'
                                    : 'Recite from this verse',
                                // One glyph, never scaled. An AnimatedSwitcher
                                // here was actively harmful: it kept both
                                // glyphs in the tree for the length of the
                                // crossfade, and the ScaleTransition brought
                                // the arriving one up from zero - so for the
                                // first frames after a tap the control had no
                                // hit area, and a quick second tap fell
                                // straight through to the card behind it.
                                // Swapping the glyph outright is the whole
                                // explanation of the state change anyway.
                                icon: Icon(
                                  isReciting
                                      ? Icons.stop_circle_outlined
                                      : Icons.play_circle_outline,
                                  color: isReciting
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                onPressed: _audioBusy
                                    ? null
                                    : () => _toggleRecitation(
                                        ayah.verseNumber,
                                        ayahs,
                                      ),
                              ),
                            IconButton(
                              tooltip: isBookmarked
                                  ? 'Remove bookmark'
                                  : 'Add bookmark',
                              icon: Icon(
                                isBookmarked
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              onPressed: () async {
                                await _toggleBookmark(ayah.verseNumber);
                              },
                            ),
                          ],
                        ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                      ],
                    ),
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

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _question;
  String? _answer;
  String? _error;
  String? _stage;

  /// Verses retrieved for this question. Shown while the answer is being
  /// composed, as progress, never as the answer's sources.
  List<String> _references = const [];

  /// Verses the answer actually cited, verified by the backend against what
  /// was retrieved. These are the only ones shown as the answer's sources: a
  /// decline has none, and offering the retrieved verses there would claim
  /// support the answer does not have.
  List<String> _citations = const [];
  bool _listening = false;
  bool _speaking = false;

  static const String _stageSearching =
      'Searching the translation for relevant verses';
  static const String _stageComposing = 'Composing an answer from those verses';

  /// Whether the off-device notice has been shown and accepted.
  static const String _voiceNoticeKey = 'voice_notice_accepted';

  /// Ask for the microphone, but only after the user has been told where their
  /// audio goes.
  ///
  /// The notice is deliberately a gate rather than a footnote: it appears before
  /// the recogniser is ever started, so nobody learns their voice left the
  /// machine after the fact. Accepting is remembered; declining is not, so the
  /// notice reappears rather than silently granting consent once.
  Future<bool> _ensureVoiceNoticeAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_voiceNoticeKey) ?? false) {
      return true;
    }
    if (!mounted) {
      return false;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Before you speak'),
        content: const Text(
          'Dictation uses your browser\'s speech service, so the audio of what '
          'you say is sent off this device to be transcribed. This app does not '
          'record or store audio, and does not keep the transcript beyond the '
          'question you choose to send.\n\n'
          'You can always type your question instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Use the microphone'),
          ),
        ],
      ),
    );

    if (accepted ?? false) {
      await prefs.setBool(_voiceNoticeKey, true);
      return true;
    }
    return false;
  }

  Future<void> _toggleListening() async {
    final voice = ref.read(voiceServiceProvider);

    if (_listening) {
      // Cleared first: stopping the recogniser also fires its own done
      // callback, and without this both paths would play the stop tone.
      setState(() => _listening = false);
      await voice.stopListening();
      await voice.playListenStopCue();
      return;
    }

    if (!await _ensureVoiceNoticeAccepted()) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _listening = true);
    // Before the recogniser opens, so the tone marks the moment the microphone
    // actually goes live rather than trailing it.
    await voice.playListenStartCue();
    await voice.startListening(
      onTranscript: (transcript, isFinal) {
        if (!mounted) {
          return;
        }
        // The transcript is only ever placed in the field. Nothing is sent
        // here, on a final result or otherwise - see _submitQuestion, which
        // only runs from the send button or the Enter key.
        setState(() {
          _controller.value = TextEditingValue(
            text: transcript,
            selection: TextSelection.collapsed(offset: transcript.length),
          );
        });
      },
      onDone: () {
        if (!mounted) {
          return;
        }
        // The recogniser can stop on its own, after a silence. That is still a
        // stop, so it gets the same tone as tapping the button.
        if (_listening) {
          voice.playListenStopCue();
        }
        setState(() => _listening = false);
      },
    );
  }

  Future<void> _toggleSpeaking() async {
    final voice = ref.read(voiceServiceProvider);
    final answer = _answer;

    if (_speaking || answer == null || answer.trim().isEmpty) {
      await voice.stopSpeaking();
      if (mounted) {
        setState(() => _speaking = false);
      }
      return;
    }

    setState(() => _speaking = true);
    // Reads the English answer only. Verse references are spoken as the
    // numbers they are; no Arabic is ever passed to the speech engine.
    await voice.speak(answer);
    if (mounted) {
      setState(() => _speaking = false);
    }
  }

  /// POST to the backend, returning the decoded body, or null after recording
  /// an error for display.
  Future<Map<String, dynamic>?> _post(String path, String question) async {
    try {
      final response = await ref
          .read(httpClientProvider)
          .post(
            Uri.parse('$kQuranBackendBaseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'question': question}),
          );

      if (!mounted) {
        return null;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      final decoded = jsonDecode(response.body);
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      setState(() {
        // The backend phrases its own errors for readers, so show them as sent.
        _error = detail is String
            ? detail
            : 'The assistant could not answer that question.';
      });
      return null;
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Unable to reach the backend at $kQuranBackendBaseUrl. '
              'The backend needs to be running.';
        });
      }
      return null;
    }
  }

  /// Ask in two steps so the wait is legible.
  ///
  /// The first call does only the refusal check and retrieval, and returns in
  /// milliseconds; the second composes the answer and is the slow one. That
  /// means a refused question is answered almost immediately, and an accepted
  /// one shows which verses were found while the answer is still being written.
  ///
  /// The answer itself is deliberately not streamed - see docs/DECISIONS.md.
  /// Streaming text would put words on screen before the citation check could
  /// run, and that check is what keeps answers grounded.
  Future<void> _submitQuestion() async {
    final question = _controller.text.trim();
    // Enter and the send button can both fire; ignore a second send while one
    // request is still outstanding.
    if (question.isEmpty || _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _question = question;
      _answer = null;
      _error = null;
      _references = const [];
      _citations = const [];
      _stage = _stageSearching;
    });

    try {
      final plan = await _post('/ask/plan', question);
      if (!mounted || plan == null) {
        return;
      }

      final references = ((plan['references'] as List<dynamic>?) ?? const [])
          .map((item) => item.toString())
          .toList();
      final planStatus = (plan['status'] as String?) ?? 'ok';

      // A refusal or a no-source answer is final; there is nothing to compose.
      if (planStatus != 'ok') {
        setState(() {
          _answer = (plan['answer'] as String?) ?? '';
          _references = references;
          _citations = const [];
        });
        return;
      }

      setState(() {
        _references = references;
        _stage = _stageComposing;
      });

      final full = await _post('/ask', question);
      if (!mounted || full == null) {
        return;
      }

      setState(() {
        _answer = (full['answer'] as String?) ?? 'No answer returned.';
        _references = ((full['references'] as List<dynamic>?) ?? const [])
            .map((item) => item.toString())
            .toList();
        // Empty on a decline, and a subset of the retrieved verses otherwise.
        _citations = ((full['citations'] as List<dynamic>?) ?? const [])
            .map((item) => item.toString())
            .toList();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _stage = null;
        });
      }
    }
  }

  /// Send on Enter, newline on Shift+Enter.
  ///
  /// Both branches are handled here rather than delegated. [TextInputAction]
  /// applies to the field as a whole and cannot tell the two apart, and once
  /// the action is `send` the field stops inserting newlines on Enter
  /// altogether - so Shift+Enter has to insert one itself or nothing happens.
  KeyEventResult _handleQuestionKey(FocusNode node, KeyEvent event) {
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertNewline();
      return KeyEventResult.handled;
    }
    _submitQuestion();
    return KeyEventResult.handled;
  }

  /// Insert a newline at the cursor, replacing any selection.
  void _insertNewline() {
    final value = _controller.value;
    final selection = value.selection;
    if (!selection.isValid) {
      _controller.value = TextEditingValue(
        text: '${value.text}\n',
        selection: TextSelection.collapsed(offset: value.text.length + 1),
      );
      return;
    }
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, '\n'),
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  /// Hand a cited verse to the reader tab.
  ///
  /// Synchronous by design: it only sets state, so the tab switch happens in
  /// the same frame as the tap. Previously this awaited a 2.9MB asset decode
  /// and then pushed a reader on top of the assistant, which left the user
  /// outside the tab they appeared to be in.
  void _openReference(String reference) {
    final target = parseReference(reference);
    if (target == null) {
      return;
    }

    ref.read(readerTargetProvider.notifier).state = target;
    ref.read(selectedTabProvider.notifier).state = kReadTabIndex;
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
      appBar: AppBar(title: const Text('Assistant')),
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
                          boxShadow: Elevation.resting(theme.brightness),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Question',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(_question!, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    if (_question != null) const SizedBox(height: 16),
                    if (_answer != null || _error != null)
                      _FadeIn(
                        // Keyed on the text so a new answer fades rather than
                        // swapping under the reader's eyes.
                        key: ValueKey<String>(_error ?? _answer ?? ''),
                        child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: Elevation.resting(theme.brightness),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Answer',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const Spacer(),
                                // Reading aloud is offered only for a real
                                // answer, never for an error message.
                                if (_answer != null &&
                                    _error == null &&
                                    (ref
                                            .watch(voiceAvailableProvider)
                                            .valueOrNull ??
                                        false))
                                  IconButton(
                                    onPressed: _toggleSpeaking,
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      _speaking
                                          ? Icons.stop_circle_outlined
                                          : Icons.volume_up_outlined,
                                      size: 20,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    tooltip: _speaking
                                        ? 'Stop reading'
                                        : 'Read this answer aloud',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error ?? _answer ?? '',
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (_citations.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                'Cited verses',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _citations
                                    .map(
                                      (reference) => ActionChip(
                                        label: Text(reference),
                                        avatar: const Icon(
                                          Icons.menu_book_outlined,
                                          size: 16,
                                        ),
                                        tooltip:
                                            'Open $reference in the reader',
                                        onPressed: () =>
                                            _openReference(reference),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ),
                    if (_loading && _stage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _ProgressCard(
                          stage: _stage!,
                          references: _references,
                          onReferenceTap: _openReference,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    // Enter sends, Shift+Enter inserts a newline. The field is
                    // multiline, so Flutter would otherwise treat Enter as
                    // newline and never call onSubmitted at all.
                    child: Focus(
                      onKeyEvent: _handleQuestionKey,
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 3,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.send,
                        // Still needed for on-screen keyboards, whose send
                        // button does not produce a physical key event.
                        onSubmitted: (_) => _submitQuestion(),
                        decoration: const InputDecoration(
                          hintText: 'Ask about a verse, topic, or theme',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Hidden rather than disabled where speech is unsupported, so
                  // it never looks like a broken control.
                  if (ref.watch(voiceAvailableProvider).valueOrNull ?? false)
                    _MicButton(
                      listening: _listening,
                      onPressed: _toggleListening,
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: _submitQuestion,
                      icon: Icon(
                        Icons.send_rounded,
                        color: theme.colorScheme.onPrimary,
                      ),
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

/// The dictation button, which has to look unmistakably live while recording.
///
/// Carries the visual half of the recording signal: a filled error-coloured
/// circle, a solid icon, and a slow pulsing ring. The tones are the audible
/// half. Either alone is enough to tell whether the microphone is open, which
/// matters for anyone running with sound off, and for anyone not looking at the
/// button when it opens.
class _MicButton extends StatefulWidget {
  const _MicButton({required this.listening, required this.onPressed});

  final bool listening;
  final VoidCallback onPressed;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening == oldWidget.listening) {
      return;
    }
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listening = widget.listening;

    // `container: true` is load-bearing, not tidiness. Without it this
    // annotation owns no semantics node of its own and is folded into the
    // IconButton's, where the tooltip already sits - and a tooltip is a
    // separate property from a label, so the button ended up with no
    // accessible name at all. Merged so a screen reader announces one toggle
    // button rather than a label and a button beside it.
    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        toggled: listening,
        label: listening ? 'Stop dictating' : 'Dictate a question',
        child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final spread = listening ? 3 + (_pulse.value * 5) : 0.0;
          return Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: listening ? theme.colorScheme.error : Colors.transparent,
              boxShadow: listening
                  ? [
                      BoxShadow(
                        color: theme.colorScheme.error.withOpacity(0.35),
                        blurRadius: spread,
                        spreadRadius: spread,
                      ),
                    ]
                  : null,
            ),
            child: child,
          );
        },
        child: IconButton(
          onPressed: widget.onPressed,
          icon: Icon(
            listening ? Icons.mic_rounded : Icons.mic_none_rounded,
            color: listening
                ? theme.colorScheme.onError
                : theme.colorScheme.onSurfaceVariant,
          ),
          tooltip: listening
              ? 'Stop dictating'
              : 'Dictate a question (audio is sent off device)',
        ),
        ),
      ),
    );
  }
}

/// What the assistant is doing right now, and what it has found so far.
///
/// Replaces a bare spinner. The stages are named rather than generic, and the
/// verses appear as soon as retrieval returns them, so the wait for the answer
/// is spent reading real results rather than watching an indicator.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.stage,
    required this.references,
    required this.onReferenceTap,
  });

  final String stage;
  final List<String> references;
  final void Function(String reference) onReferenceTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  stage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (references.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              references.length == 1
                  ? 'Found 1 verse'
                  : 'Found ${references.length} verses',
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: references
                  .map(
                    (reference) => ActionChip(
                      label: Text(reference),
                      avatar: const Icon(Icons.menu_book_outlined, size: 16),
                      tooltip: 'Open $reference in the reader',
                      onPressed: () => onReferenceTap(reference),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
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
    // A Material, not a plain coloured Container. ListTile paints its ink on
    // the nearest Material ancestor, so a decorated box in between hides every
    // splash - Flutter asserts on exactly this, which meant the settings sheet
    // was throwing in debug the moment it opened.
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Reciter picker for whole-surah mode.
///
/// Separate from the verse-by-verse picker because the lists come from
/// different providers with different completeness: mp3quran publishes hundreds
/// of recitations, many of them partial, so incomplete sets are labelled rather
/// than silently failing on the surahs they lack.
class _FullSurahReciterPicker extends ConsumerWidget {
  const _FullSurahReciterPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(surahRecitationProvider);
    final available = ref.watch(fullSurahRecitationsProvider);

    return available.when(
      loading: () => const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Loading reciters...'),
      ),
      error: (error, _) => const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Reciters unavailable'),
        subtitle: Text('Recitation needs a connection. Reading does not.'),
      ),
      data: (recitations) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Reciter (${recitations.length} available)'),
        subtitle: Text(selected?.label ?? 'Choose a reciter'),
        trailing: SizedBox(
          width: 190,
          child: DropdownButton<SurahRecitation>(
            value: selected,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final recitation in recitations)
                DropdownMenuItem(
                  value: recitation,
                  child: Text(
                    recitation.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (recitation) {
              if (recitation != null) {
                ref.read(surahRecitationProvider.notifier).select(recitation);
              }
            },
          ),
        ),
      ),
    );
  }
}

/// The surah header: identity gradient, names, metadata pills and the opening
/// Bismillah.
///
/// The Bismillah is rendered from the corpus field the importer stores, never
/// typed out here. Surah 1 has it as verse 1 and surah 9 has none, so both
/// correctly render without it.
class _SurahHeaderCard extends StatelessWidget {
  const _SurahHeaderCard({required this.surah});

  final SurahSummary surah;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bismillah = surah.bismillah;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AmbientBackdrop(
        child: GradientCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 20, 20),
        patternTile: 66,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The reader's anchor: which surah of the 114 this is. It was
                // previously only in the app bar as part of a text line, which
                // made it the least findable fact on the screen.
                NumberBadge(
                  surah.number,
                  onGradient: true,
                  diameter: 56,
                  ringed: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        surah.nameSimple,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        surah.nameTransliterated,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  surah.nameArabic,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontFamily: 'AmiriQuran',
                    fontSize: 26,
                    height: 1.6,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MetaPill(surah.revelationPlace),
                MetaPill('${surah.verseCount} ayahs'),
              ],
            ),
            if (bismillah != null) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  bismillah,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AmiriQuran',
                    fontSize: 22,
                    height: 1.9,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

/// Fades its child in on first build, and again whenever its key changes.
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.child, super.key});

  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.normal,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Motion.curve),
      child: widget.child,
    );
  }
}
