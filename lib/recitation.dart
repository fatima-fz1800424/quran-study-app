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
    final loaded = ((body['recitations'] as List<dynamic>?) ?? const [])
        .map(
          (item) => Reciter(
            id: item['id'] as int,
            name: (item['reciter_name'] as String?) ?? 'Unknown',
            style: item['style'] as String?,
          ),
        )
        .toList();
    _reciters = loaded;
    return loaded;
  }

  @override
  Future<RecitationSource?> resolveSource(Reciter reciter) async {
    final cached = _sources[reciter.id];
    if (cached != null) {
      return cached;
    }
    // Any ayah will do; its path yields the template for all of them.
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
    final source = RecitationSource(reciter: reciter, template: template);
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
