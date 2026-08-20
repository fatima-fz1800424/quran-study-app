import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Seam over the platform speech plugins.
///
/// The assistant UI talks to this rather than to the plugins directly, so its
/// behaviour - above all that a transcript is never sent without the user
/// pressing send - can be tested without a microphone or a speech service.
abstract class VoiceService {
  /// Whether dictation is usable here at all. False on platforms with no
  /// speech support, so the UI can hide the control rather than offer
  /// something that will fail.
  Future<bool> prepare();

  /// Begin dictating. [onTranscript] is called with the words so far;
  /// `isFinal` marks the recogniser's last result for this utterance.
  ///
  /// Implementations must not act on a final result beyond reporting it. The
  /// decision to send belongs to the user.
  Future<void> startListening({
    required void Function(String transcript, bool isFinal) onTranscript,
    required void Function() onDone,
  });

  Future<void> stopListening();

  /// Read [text] aloud. English only - see [PlatformVoiceService.speak].
  Future<void> speak(String text);

  Future<void> stopSpeaking();

  /// Short tone marking the microphone opening, and a different one for it
  /// closing. Sound is a second channel alongside the button's own state, for
  /// anyone not watching the button - and the visual state covers anyone with
  /// sound off, so neither signal is load-bearing on its own.
  Future<void> playListenStartCue();

  Future<void> playListenStopCue();
}

class PlatformVoiceService implements VoiceService {
  PlatformVoiceService({SpeechToText? speech, FlutterTts? tts})
      : _speech = speech ?? SpeechToText(),
        _tts = tts ?? FlutterTts();

  final SpeechToText _speech;
  final FlutterTts _tts;
  bool _prepared = false;
  AudioPlayer? _startCue;
  AudioPlayer? _stopCue;

  @override
  Future<bool> prepare() async {
    if (_prepared) {
      return _speech.isAvailable;
    }
    try {
      _prepared = await _speech.initialize();
    } catch (_) {
      // An unsupported browser throws rather than returning false.
      _prepared = false;
    }
    return _prepared;
  }

  @override
  Future<void> startListening({
    required void Function(String transcript, bool isFinal) onTranscript,
    required void Function() onDone,
  }) async {
    if (!await prepare()) {
      onDone();
      return;
    }
    await _speech.listen(
      onResult: (result) => onTranscript(
        result.recognizedWords,
        result.finalResult,
      ),
    );
  }

  @override
  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  /// Speaks [text] with the platform's English voice.
  ///
  /// Only ever given the assistant's English answer. Quranic Arabic is never
  /// passed here: a general-purpose English voice mispronounces it, and the
  /// project rule against producing Quranic text from anything but the verified
  /// corpus applies to audio as much as to characters on screen.
  @override
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    await _tts.setLanguage('en-US');
    await _tts.speak(text);
  }

  @override
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  @override
  Future<void> playListenStartCue() => _playCue(
        _startCue ??= AudioPlayer(),
        'assets/sounds/mic_start.wav',
      );

  @override
  Future<void> playListenStopCue() => _playCue(
        _stopCue ??= AudioPlayer(),
        'assets/sounds/mic_stop.wav',
      );

  /// Play a cue, reusing one player per sound so repeated taps do not each
  /// allocate one. A cue that fails is not worth surfacing: the button's own
  /// state already says whether the microphone is open.
  Future<void> _playCue(AudioPlayer player, String asset) async {
    try {
      if (player.audioSource == null) {
        await player.setAsset(asset);
      }
      await player.seek(Duration.zero);
      await player.play();
    } catch (_) {
      // Ignored on purpose - see above.
    }
  }

  Future<void> dispose() async {
    await _startCue?.dispose();
    await _stopCue?.dispose();
  }
}

final voiceServiceProvider = Provider<VoiceService>(
  (ref) => PlatformVoiceService(),
);

/// Whether dictation is usable, resolved once at first use.
final voiceAvailableProvider = FutureProvider<bool>((ref) async {
  // No dictation in tests unless a fake service says otherwise.
  return ref.watch(voiceServiceProvider).prepare();
});

/// A fake for tests: records what it was asked to do and reports whatever
/// transcript the test hands it.
@visibleForTesting
class FakeVoiceService implements VoiceService {
  FakeVoiceService({this.available = true});

  final bool available;
  bool listening = false;
  final List<String> spoken = <String>[];
  final List<String> cues = <String>[];
  int stopSpeakingCalls = 0;

  void Function(String transcript, bool isFinal)? _onTranscript;
  void Function()? _onDone;

  @override
  Future<bool> prepare() async => available;

  @override
  Future<void> startListening({
    required void Function(String transcript, bool isFinal) onTranscript,
    required void Function() onDone,
  }) async {
    if (!available) {
      onDone();
      return;
    }
    listening = true;
    _onTranscript = onTranscript;
    _onDone = onDone;
  }

  @override
  Future<void> stopListening() async {
    listening = false;
    _onDone?.call();
  }

  /// Simulate the recogniser producing words.
  void emit(String transcript, {bool isFinal = false}) {
    _onTranscript?.call(transcript, isFinal);
  }

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stopSpeaking() async {
    stopSpeakingCalls++;
  }

  @override
  Future<void> playListenStartCue() async {
    cues.add('start');
  }

  @override
  Future<void> playListenStopCue() async {
    cues.add('stop');
  }
}
