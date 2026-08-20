import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quran.com's recitation metadata. No key required, and it answers with
/// `Access-Control-Allow-Origin: *`, so the browser can call it directly.
const String kRecitationsEndpoint =
    'https://api.quran.com/api/v4/resources/recitations?language=en';
const String kRecitationAyahEndpoint =
    'https://api.quran.com/api/v4/recitations';

/// Relative paths from the API resolve against this host.
const String kVersesCdn = 'https://verses.quran.com';

/// Hosts we are willing to stream recitation from.
///
/// Quran.com's API resolves three of its twelve reciters to
/// `mirrors.quranicaudio.com/everyayah/...`, which is EveryAyah's audio.
/// EveryAyah publishes no copyright notice, licence or terms for its audio -
/// its only stated terms cover the separate timing files - and absence of a
/// prohibition is not permission. Those reciters are therefore excluded, even
/// though Quran.com serves them.
///
/// This filters by host rather than by reciter id on purpose. An id list would
/// silently start streaming from a mirror again the day Quran.com re-points a
/// reciter; a host allowlist makes that reciter disappear instead.
const Set<String> kAllowedAudioHosts = {
  'verses.quran.com',
  'audio.qurancdn.com',
};

/// Whether [url] is on a host we may stream from. See [kAllowedAudioHosts].
bool isAllowedAudioUrl(String url) {
  final host = Uri.tryParse(url)?.host;
  return host != null && host.isNotEmpty && kAllowedAudioHosts.contains(host);
}

/// Placeholder for the zero-padded `SSSAAA` verse token in a URL template.
const String kRefPlaceholder = '{ref}';

class Reciter {
  const Reciter({required this.id, required this.name, this.style});

  final int id;
  final String name;
  final String? style;

  String get label => style == null || style!.isEmpty ? name : '$name ($style)';

  @override
  bool operator ==(Object other) => other is Reciter && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The `SSSAAA` token the audio filenames use, e.g. 2:255 -> `002255`.
String verseToken(int surah, int verse) =>
    '${surah.toString().padLeft(3, '0')}${verse.toString().padLeft(3, '0')}';

/// Turn one API audio path into a template for every other ayah.
///
/// The API is not consistent about this, which is why it has to be derived
/// rather than assumed. Nine of the twelve reciters return a path relative to
/// verses.quran.com, such as `Alafasy/mp3/002255.mp3`. Three return a
/// protocol-relative absolute URL to a mirror instead, such as
/// `//mirrors.quranicaudio.com/everyayah/Husary_64kbps/002255.mp3`. Both shapes
/// carry the same six-digit verse token, so replacing it yields a template that
/// covers the whole corpus from a single request.
///
/// Returns null if no verse token is present, rather than guessing.
String? audioTemplateFromApiPath(String apiPath) {
  final path = apiPath.trim();
  if (path.isEmpty) {
    return null;
  }

  final String absolute;
  if (path.startsWith('//')) {
    absolute = 'https:$path';
  } else if (path.startsWith('http://')) {
    // Never downgrade: a mixed-content request is blocked on the web anyway.
    absolute = path.replaceFirst('http://', 'https://');
  } else if (path.startsWith('https://')) {
    absolute = path;
  } else {
    absolute = '$kVersesCdn/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  // Replace the last six-digit run, so a reciter folder containing digits
  // (Husary_64kbps) is not mistaken for the verse token.
  final matches = RegExp(r'\d{6}').allMatches(absolute).toList();
  if (matches.isEmpty) {
    return null;
  }
  final token = matches.last;
  return absolute.replaceRange(token.start, token.end, kRefPlaceholder);
}

/// What the reader needs to play a surah: a template plus the reciter it came
/// from.
class RecitationSource {
  const RecitationSource({required this.reciter, required this.template});

  final Reciter reciter;
  final String template;

  String urlFor(int surah, int verse) =>
      template.replaceAll(kRefPlaceholder, verseToken(surah, verse));
}

/// Seam over the network and the audio player, so the reader's playback
/// behaviour can be tested without either.
abstract class RecitationService {
  Future<List<Reciter>> loadReciters();

  /// Resolve a reciter's URL template, one request per reciter, memoised.
  Future<RecitationSource?> resolveSource(Reciter reciter);

  /// Play [verses] of [surah] in order from [startVerse].
  ///
  /// [onVerse] fires as each ayah begins, which is what drives highlighting and
  /// auto-scroll; [onDone] fires when the queue finishes or is stopped.
  Future<void> play({
    required RecitationSource source,
    required int surah,
    required List<int> verses,
    required int startVerse,
    required void Function(int verse) onVerse,
    required void Function() onDone,
  });

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();

  bool get isPlaying;
}

class PlatformRecitationService implements RecitationService {
  PlatformRecitationService({http.Client? client, AudioPlayer? player})
      : _client = client ?? http.Client(),
        _player = player ?? AudioPlayer();

  final http.Client _client;
  final AudioPlayer _player;
  final Map<int, RecitationSource> _sources = {};
  List<Reciter>? _reciters;

  @override
  bool get isPlaying => _player.playing;

  @override
  Future<List<Reciter>> loadReciters() async {
    final cached = _reciters;
    if (cached != null) {
      return cached;
    }
    final response = await _client.get(Uri.parse(kRecitationsEndpoint));
    if (response.statusCode != 200) {
      throw StateError('Could not load reciters: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final announced = ((body['recitations'] as List<dynamic>?) ?? const [])
        .map(
          (item) => Reciter(
            id: item['id'] as int,
            name: (item['reciter_name'] as String?) ?? 'Unknown',
            style: item['style'] as String?,
          ),
        )
        .toList();

    // Resolve every template up front so the host allowlist can be applied
    // before a reciter is ever offered. Done in parallel; it is one small
    // request each, once per session.
    final resolved = await Future.wait(announced.map(_fetchSource));
    final allowed = <Reciter>[];
    for (final source in resolved) {
      if (source == null || !isAllowedAudioUrl(source.template)) {
        continue;
      }
      _sources[source.reciter.id] = source;
      allowed.add(source.reciter);
    }

    _reciters = allowed;
    return allowed;
  }

  /// Fetch a reciter's URL template. Any ayah will do; its path yields the
  /// template for all of them.
  Future<RecitationSource?> _fetchSource(Reciter reciter) async {
    try {
      final response = await _client.get(
        Uri.parse('$kRecitationAyahEndpoint/${reciter.id}/by_ayah/1:1'),
      );
      if (response.statusCode != 200) {
        return null;
      }
      final files = (jsonDecode(response.body)
          as Map<String, dynamic>)['audio_files'] as List<dynamic>?;
      if (files == null || files.isEmpty) {
        return null;
      }
      final template = audioTemplateFromApiPath(
        (files.first as Map<String, dynamic>)['url'] as String? ?? '',
      );
      if (template == null) {
        return null;
      }
      return RecitationSource(reciter: reciter, template: template);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<RecitationSource?> resolveSource(Reciter reciter) async {
    final cached = _sources[reciter.id];
    if (cached != null) {
      return cached;
    }
    // Not normally reached: loadReciters resolves and caches everything it
    // returns. Re-checked here anyway so no path can bypass the allowlist.
    final source = await _fetchSource(reciter);
    if (source == null || !isAllowedAudioUrl(source.template)) {
      return null;
    }
    _sources[reciter.id] = source;
    return source;
  }

  @override
  Future<void> play({
    required RecitationSource source,
    required int surah,
    required List<int> verses,
    required int startVerse,
    required void Function(int verse) onVerse,
    required void Function() onDone,
  }) async {
    final ordered = [...verses]..sort();
    final startIndex = ordered.indexOf(startVerse);

    await _player.stop();
    // One player with a queue, rather than a player per ayah: browsers gate
    // audible playback on a user gesture, and a fresh element created later in
    // the sequence can be blocked. A queue also gives gapless playback.
    await _player.setAudioSources(
      [
        for (final verse in ordered)
          AudioSource.uri(Uri.parse(source.urlFor(surah, verse))),
      ],
      initialIndex: startIndex < 0 ? 0 : startIndex,
    );

    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < ordered.length) {
        onVerse(ordered[index]);
      }
    });
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        onDone();
      }
    });

    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.play();

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() => _player.dispose();
}

final recitationServiceProvider = Provider<RecitationService>(
  (ref) => PlatformRecitationService(),
);

/// The available reciters, loaded once. Recitation needs a connection, so this
/// is allowed to fail without affecting reading.
final recitersProvider = FutureProvider<List<Reciter>>((ref) async {
  final reciters = await ref.watch(recitationServiceProvider).loadReciters();
  // Restore the stored choice as soon as the list is known.
  await ref.read(reciterProvider.notifier).restore(reciters);
  return reciters;
});

/// The reciter the user picked, remembered across sessions.
class ReciterNotifier extends StateNotifier<Reciter?> {
  ReciterNotifier() : super(null);

  static const String _key = 'selected_reciter_id';

  /// Restore the stored choice, defaulting to the first available reciter.
  Future<void> restore(List<Reciter> available) async {
    if (available.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getInt(_key);
    state = available.firstWhere(
      (reciter) => reciter.id == storedId,
      orElse: () => available.first,
    );
  }

  Future<void> select(Reciter reciter) async {
    state = reciter;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, reciter.id);
  }
}

final reciterProvider = StateNotifierProvider<ReciterNotifier, Reciter?>(
  (ref) => ReciterNotifier(),
);

// ---------------------------------------------------------------------------
// Full-surah recitation
// ---------------------------------------------------------------------------

/// mp3quran.net publishes whole-surah audio for far more reciters than any
/// ayah-level source, which is the whole reason this second mode exists. Their
/// terms grant use explicitly - see docs/DECISIONS.md for the quoted text and
/// for the limits of that grant.
const String kFullSurahRecitersEndpoint =
    'https://www.mp3quran.net/api/v3/reciters?language=eng';

/// Whole-surah audio is only streamed from mp3quran's own servers.
///
/// Same reasoning as [kAllowedAudioHosts]: the permission we are relying on is
/// theirs, so a URL that points anywhere else is not covered by it. They serve
/// from numbered hosts (server6, server16, ...), so this matches the domain
/// rather than an enumerated list.
bool isAllowedFullSurahUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == 'mp3quran.net' || host.endsWith('.mp3quran.net');
}

/// One reciter's whole-surah set. A reciter may publish several, so this is a
/// recitation rather than a reciter.
class SurahRecitation {
  const SurahRecitation({
    required this.reciterId,
    required this.reciterName,
    required this.moshafName,
    required this.server,
    required this.availableSurahs,
  });

  final int reciterId;
  final String reciterName;
  final String moshafName;
  final String server;

  /// Which surahs this set actually contains. Many are incomplete, so this is
  /// checked before offering playback rather than after failing to fetch.
  final Set<int> availableSurahs;

  /// Stable identity for persistence: a reciter can have more than one set.
  String get key => '$reciterId|$moshafName';

  String get label =>
      availableSurahs.length == 114 ? reciterName : '$reciterName (partial)';

  bool hasSurah(int surah) => availableSurahs.contains(surah);

  String urlFor(int surah) =>
      '$server${surah.toString().padLeft(3, '0')}.mp3';
}

/// Parse the mp3quran reciters payload into whole-surah recitations.
///
/// Kept pure so the shape of their API is pinned by tests: entries whose server
/// is off-domain, or which list no surahs, are dropped rather than offered.
List<SurahRecitation> parseFullSurahRecitations(Map<String, dynamic> body) {
  final out = <SurahRecitation>[];
  for (final entry in (body['reciters'] as List<dynamic>? ?? const [])) {
    final reciter = entry as Map<String, dynamic>;
    final id = reciter['id'];
    final name = reciter['name'];
    if (id is! int || name is! String || name.trim().isEmpty) {
      continue;
    }
    for (final rawMoshaf in (reciter['moshaf'] as List<dynamic>? ?? const [])) {
      final moshaf = rawMoshaf as Map<String, dynamic>;
      final server = (moshaf['server'] as String?)?.trim() ?? '';
      if (server.isEmpty || !isAllowedFullSurahUrl(server)) {
        continue;
      }
      final surahs = <int>{};
      for (final part in (moshaf['surah_list'] as String? ?? '').split(',')) {
        final parsed = int.tryParse(part.trim());
        if (parsed != null && parsed >= 1 && parsed <= 114) {
          surahs.add(parsed);
        }
      }
      if (surahs.isEmpty) {
        continue;
      }
      out.add(
        SurahRecitation(
          reciterId: id,
          reciterName: name.trim(),
          moshafName: (moshaf['name'] as String?)?.trim() ?? '',
          // Their servers are inconsistent about the trailing slash.
          server: server.endsWith('/') ? server : '$server/',
          availableSurahs: surahs,
        ),
      );
    }
  }
  out.sort((a, b) => a.reciterName.compareTo(b.reciterName));
  return out;
}

/// Seam for whole-surah playback.
abstract class FullSurahService {
  Future<List<SurahRecitation>> loadRecitations();

  Future<void> play(String url, {required void Function() onDone});

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();

  bool get isPlaying;
}

class PlatformFullSurahService implements FullSurahService {
  PlatformFullSurahService({http.Client? client, AudioPlayer? player})
      : _client = client ?? http.Client(),
        _player = player ?? AudioPlayer();

  final http.Client _client;
  final AudioPlayer _player;
  List<SurahRecitation>? _cached;

  @override
  bool get isPlaying => _player.playing;

  @override
  Future<List<SurahRecitation>> loadRecitations() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final response = await _client.get(Uri.parse(kFullSurahRecitersEndpoint));
    if (response.statusCode != 200) {
      throw StateError('Could not load reciters: HTTP ${response.statusCode}');
    }
    final parsed = parseFullSurahRecitations(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    _cached = parsed;
    return parsed;
  }

  @override
  Future<void> play(String url, {required void Function() onDone}) async {
    if (!isAllowedFullSurahUrl(url)) {
      throw StateError('Refusing to stream from an unexpected host: $url');
    }
    await _player.stop();
    await _player.setUrl(url);
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        onDone();
      }
    });
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}

final fullSurahServiceProvider = Provider<FullSurahService>(
  (ref) => PlatformFullSurahService(),
);

final fullSurahRecitationsProvider =
    FutureProvider<List<SurahRecitation>>((ref) async {
  final list = await ref.watch(fullSurahServiceProvider).loadRecitations();
  await ref.read(surahRecitationProvider.notifier).restore(list);
  return list;
});

/// The chosen whole-surah recitation, remembered across sessions.
class SurahRecitationNotifier extends StateNotifier<SurahRecitation?> {
  SurahRecitationNotifier() : super(null);

  static const String _key = 'full_surah_recitation';

  Future<void> restore(List<SurahRecitation> available) async {
    if (available.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString(_key);
    state = available.firstWhere(
      (item) => item.key == storedKey,
      // Prefer a complete recitation as the default; a partial one would look
      // broken on whichever surahs it lacks.
      orElse: () => available.firstWhere(
        (item) => item.availableSurahs.length == 114,
        orElse: () => available.first,
      ),
    );
  }

  Future<void> select(SurahRecitation recitation) async {
    state = recitation;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, recitation.key);
  }
}

final surahRecitationProvider =
    StateNotifierProvider<SurahRecitationNotifier, SurahRecitation?>(
  (ref) => SurahRecitationNotifier(),
);

/// How the reader plays audio.
///
/// Two modes because the sources differ, not as a preference: verse-level
/// playback needs one file per ayah, which only a few reciters publish, while
/// whole-surah files are available for hundreds but carry no ayah boundaries to
/// highlight or scroll to.
enum RecitationMode { verseByVerse, fullSurah }

class RecitationModeNotifier extends StateNotifier<RecitationMode> {
  RecitationModeNotifier() : super(RecitationMode.verseByVerse) {
    _restore();
  }

  static const String _key = 'recitation_mode';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_key) == 'fullSurah') {
      state = RecitationMode.fullSurah;
    }
  }

  Future<void> select(RecitationMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final recitationModeProvider =
    StateNotifierProvider<RecitationModeNotifier, RecitationMode>(
  (ref) => RecitationModeNotifier(),
);

/// A fake for tests: records calls and lets the test drive verse progression.
@visibleForTesting
class FakeRecitationService implements RecitationService {
  FakeRecitationService({
    this.reciters = const [
      Reciter(id: 7, name: 'Mishari Rashid al-`Afasy'),
      Reciter(id: 2, name: 'AbdulBaset AbdulSamad', style: 'Murattal'),
    ],
    this.template = 'https://verses.quran.com/Alafasy/mp3/$kRefPlaceholder.mp3',
  });

  final List<Reciter> reciters;
  final String template;

  final List<String> requestedUrls = [];
  bool playing = false;
  int pauseCalls = 0;
  int stopCalls = 0;
  void Function(int verse)? _onVerse;
  void Function()? _onDone;

  @override
  bool get isPlaying => playing;

  @override
  Future<List<Reciter>> loadReciters() async => reciters;

  @override
  Future<RecitationSource?> resolveSource(Reciter reciter) async =>
      RecitationSource(reciter: reciter, template: template);

  @override
  Future<void> play({
    required RecitationSource source,
    required int surah,
    required List<int> verses,
    required int startVerse,
    required void Function(int verse) onVerse,
    required void Function() onDone,
  }) async {
    final ordered = [...verses]..sort();
    requestedUrls
      ..clear()
      ..addAll(ordered.map((verse) => source.urlFor(surah, verse)));
    playing = true;
    _onVerse = onVerse;
    _onDone = onDone;
    onVerse(startVerse);
  }

  /// Simulate the queue advancing.
  void advanceTo(int verse) => _onVerse?.call(verse);

  /// Simulate the queue finishing.
  void finish() {
    playing = false;
    _onDone?.call();
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<void> resume() async {
    playing = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
  }
}

/// A fake whole-surah service for tests.
@visibleForTesting
class FakeFullSurahService implements FullSurahService {
  FakeFullSurahService({List<SurahRecitation>? recitations})
      : recitations = recitations ??
            const [
              SurahRecitation(
                reciterId: 273,
                reciterName: 'Haitham Aldukhain',
                moshafName: "Rewayat Hafs A'n Assem",
                server: 'https://server16.mp3quran.net/h_dukhain/x/',
                availableSurahs: {1, 2, 36, 112, 114},
              ),
              SurahRecitation(
                reciterId: 99,
                reciterName: 'Partial Reciter',
                moshafName: 'Partial',
                server: 'https://server9.mp3quran.net/partial/',
                availableSurahs: {1},
              ),
            ];

  final List<SurahRecitation> recitations;

  final List<String> played = [];
  bool playing = false;
  int stopCalls = 0;
  int pauseCalls = 0;
  void Function()? _onDone;

  @override
  bool get isPlaying => playing;

  @override
  Future<List<SurahRecitation>> loadRecitations() async => recitations;

  @override
  Future<void> play(String url, {required void Function() onDone}) async {
    played.add(url);
    playing = true;
    _onDone = onDone;
  }

  /// Simulate the surah finishing.
  void finish() {
    playing = false;
    _onDone?.call();
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<void> resume() async {
    playing = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
  }
}
