// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_study_app/main.dart';
import 'package:quran_study_app/recitation.dart';
import 'package:quran_study_app/surah_list_page.dart';
import 'package:quran_study_app/voice.dart';

/// A stand-in surah for reader tests. Only `number` affects what these tests
/// assert, and the Arabic name is left empty rather than typed out, so no
/// Quranic text or name is reproduced here. Loading the real surah from the
/// bundle is not an option in `testWidgets`: `rootBundle` needs real async,
/// which the fake-async test zone does not run.
const SurahSummary _testSurah = SurahSummary(
  number: 2,
  nameArabic: '',
  nameSimple: 'The Cow',
  nameTransliterated: 'Al-Baqara',
  revelationPlace: 'madinah',
  verseCount: 286,
);

/// A small synthetic corpus. The Arabic field is placeholder Latin text on
/// purpose: no Quranic Arabic is generated here, and these tests only care
/// about verse numbering and layout.
Map<String, dynamic> _fakeCorpus({int verses = 60}) => {
      'surahs': [
        for (final surah in [
          {'number': 2, 'name': 'Al-Baqarah', 'place': 'madinah'},
          {'number': 36, 'name': 'Ya-Sin', 'place': 'makkah'},
        ])
          {
            'number': surah['number'],
            'name_arabic': '',
            'name_simple': surah['name'],
            'name_transliterated': surah['name'],
            'revelation_place': surah['place'],
            'verse_count': verses,
            'ayahs': [
              for (var v = 1; v <= verses; v++)
                {
                  'verse_number': v,
                  'text': 'placeholder arabic line $v',
                  'translation': 'Placeholder translation for verse $v.',
                },
            ],
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Quran app loads the surah list', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: QuranStudyApp()));

    expect(find.text('Quran'), findsOneWidget);
    expect(find.text('Reader'), findsNothing);
  });

  testWidgets('assistant shows the study-aid disclaimer with no interaction', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: QuranStudyApp()));

    // Switch to the Assistant tab the way a user would. Only the nav label is
    // on stage here; the offstage tab's own AppBar title is not matched.
    await tester.tap(find.text('Assistant'));
    await tester.pump();

    // The disclaimer is a required guardrail: on screen as soon as the tab
    // opens, with no scrolling and no menu, and no way to dismiss it.
    final disclaimer = find.textContaining(
      'not a substitute for a qualified scholar',
    );
    expect(disclaimer, findsOneWidget);
    expect(find.textContaining('Yusuf Ali translation'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('opening the reader records the last-read position', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReaderPage(surah: _testSurah)),
      ),
    );
    // Deliberately not pumpAndSettle: the reader shows a progress indicator
    // while the corpus loads, and that animation never settles. One frame runs
    // the post-frame callback that records the position.
    await tester.pump();

    // Reading is enough on its own: last-read must not depend on bookmarking.
    expect(container.read(lastReadProvider)?.surahNumber, 2);
    expect(container.read(lastReadProvider)?.ayahNumber, 1);
  });

  testWidgets('jumping to an ayah records that ayah as the read position', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ReaderPage(surah: _testSurah, initialAyah: 255),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(lastReadProvider)?.surahNumber, 2);
    expect(container.read(lastReadProvider)?.ayahNumber, 255);
  });

  testWidgets('a citation can move the user to the reader tab', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const QuranStudyApp(),
      ),
    );
    expect(container.read(selectedTabProvider), kReadTabIndex);

    // What tapping a citation chip does: set the target, switch the tab. Both
    // are plain state writes, so the switch lands in the same frame.
    container.read(readerTargetProvider.notifier).state =
        const ReaderTarget(surahNumber: 16, ayahNumber: 127);
    container.read(selectedTabProvider.notifier).state = kAssistantTabIndex;
    await tester.pump();

    expect(container.read(selectedTabProvider), kAssistantTabIndex);
    expect(
      find.textContaining('not a substitute for a qualified scholar'),
      findsOneWidget,
    );
  });

  testWidgets('Shift+Enter adds a newline, Enter submits', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const QuranStudyApp(),
      ),
    );
    container.read(selectedTabProvider.notifier).state = kAssistantTabIndex;
    await tester.pump();

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'first line');

    // Shift+Enter must stay in the field as a newline.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(
      tester.widget<TextField>(field).controller!.text,
      contains('\n'),
      reason: 'Shift+Enter should insert a newline, not submit',
    );
    expect(find.text('Question'), findsNothing);

    // Plain Enter submits: the question card appears, set synchronously before
    // the request goes out.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Question'), findsOneWidget);
  });

  testWidgets('reading a second surah replaces the first as the resume point', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    QuranDataLoader.seedCorpusForTests(_fakeCorpus());
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final surahs = await QuranDataLoader.loadSurahs();
    final baqarah = surahs.firstWhere((s) => s.number == 2);
    final yaSin = surahs.firstWhere((s) => s.number == 36);

    Future<void> open(SurahSummary surah) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ReaderPage(
              key: ValueKey('reader-${surah.number}'),
              surah: surah,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await open(baqarah);
    expect(container.read(lastReadProvider)?.surahNumber, 2);

    // The bug this guards: the resume point stayed on whatever was stored
    // first, no matter how many other surahs were opened afterwards.
    await open(yaSin);
    expect(container.read(lastReadProvider)?.surahNumber, 36);

  });

  testWidgets('scrolling partway updates the recorded ayah', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    QuranDataLoader.seedCorpusForTests(_fakeCorpus());
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final surahs = await QuranDataLoader.loadSurahs();
    final baqarah = surahs.firstWhere((s) => s.number == 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReaderPage(surah: baqarah)),
      ),
    );
    // Let the seeded corpus resolve and the list lay out.
    await tester.pump();
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
    expect(container.read(lastReadProvider)?.ayahNumber, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pump();
    // Past the scroll-settle debounce.
    await tester.pump(const Duration(milliseconds: 400));

    final recorded = container.read(lastReadProvider);
    expect(recorded?.surahNumber, 2);
    expect(
      recorded?.ayahNumber,
      greaterThan(1),
      reason: 'scrolling should move the read position off verse 1',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_read_ayah'), recorded?.ayahNumber);
  });

  testWidgets('every scroll updates the ayah, not just the first', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    QuranDataLoader.seedCorpusForTests(_fakeCorpus());
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final surahs = await QuranDataLoader.loadSurahs();
    final baqarah = surahs.firstWhere((s) => s.number == 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReaderPage(surah: baqarah)),
      ),
    );
    await tester.pump();
    await tester.pump();

    int recorded() => container.read(lastReadProvider)?.ayahNumber ?? -1;
    expect(recorded(), 1);

    final seen = <int>[recorded()];
    for (var step = 0; step < 3; step++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      seen.add(recorded());
    }

    // Each scroll must move the recorded position on. Freezing after the first
    // is the reported bug.
    for (var i = 1; i < seen.length; i++) {
      expect(
        seen[i],
        greaterThan(seen[i - 1]),
        reason: 'scroll $i did not advance the recorded ayah: $seen',
      );
    }
  });

  testWidgets('leaving straight after a scroll still records the position', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    QuranDataLoader.seedCorpusForTests(_fakeCorpus());
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final surahs = await QuranDataLoader.loadSurahs();
    final baqarah = surahs.firstWhere((s) => s.number == 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReaderPage(surah: baqarah)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(container.read(lastReadProvider)?.ayahNumber, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    // Leave immediately, without waiting out the settle delay. A reader who
    // scrolls and taps back must not lose their place.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
      ),
    );
    await tester.pump();

    expect(
      container.read(lastReadProvider)?.ayahNumber,
      greaterThan(1),
      reason: 'the scrolled position was lost when the reader closed',
    );
  });

  testWidgets('a throttled scroll is still flushed when the reader closes', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    QuranDataLoader.seedCorpusForTests(_fakeCorpus());
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final surahs = await QuranDataLoader.loadSurahs();
    final baqarah = surahs.firstWhere((s) => s.number == 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReaderPage(surah: baqarah)),
      ),
    );
    await tester.pump();
    await tester.pump();

    // First scroll writes immediately and opens the throttle window.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    final afterFirst = container.read(lastReadProvider)!.ayahNumber;
    expect(afterFirst, greaterThan(1));

    // Second scroll lands inside that window, so it is observed but not
    // written - the position a reader would lose by leaving right now.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(container.read(lastReadProvider)!.ayahNumber, afterFirst);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
      ),
    );
    await tester.pump();

    expect(
      container.read(lastReadProvider)!.ayahNumber,
      greaterThan(afterFirst),
      reason: 'closing the reader must flush the throttled position',
    );
  });

  test('the last-read notifier writes through and dedupes', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(lastReadProvider.notifier);
    await notifier.save(18, 67);
    expect(container.read(lastReadProvider)?.surahNumber, 18);

    // Same position again is a no-op; a different one must land.
    await notifier.save(18, 67);
    await notifier.save(2, 255);
    expect(container.read(lastReadProvider)?.surahNumber, 2);
    expect(container.read(lastReadProvider)?.ayahNumber, 255);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_read_surah'), 2);
    expect(prefs.getInt('last_read_ayah'), 255);
  });

  /// Pump the app on the Assistant tab with a fake speech service and the
  /// off-device notice already accepted.
  Future<FakeVoiceService> pumpAssistantWithVoice(
    WidgetTester tester, {
    bool available = true,
    bool noticeAccepted = true,
  }) async {
    SharedPreferences.setMockInitialValues(
      noticeAccepted ? {'voice_notice_accepted': true} : {},
    );
    final fake = FakeVoiceService(available: available);
    final container = ProviderContainer(
      overrides: [voiceServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const QuranStudyApp(),
      ),
    );
    container.read(selectedTabProvider.notifier).state = kAssistantTabIndex;
    await tester.pump();
    await tester.pump();
    return fake;
  }

  testWidgets('a final transcript is never sent on its own', (
    WidgetTester tester,
  ) async {
    final voice = await pumpAssistantWithVoice(tester);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    expect(voice.listening, isTrue);

    voice.emit('what does the Quran say about patience', isFinal: true);
    await tester.pump();

    // The words land in the field for review...
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'what does the Quran say about patience',
    );
    // ...and nothing was sent. A final result is the recogniser being done,
    // not the user deciding to ask.
    expect(find.text('Question'), findsNothing);

    // Only the send action submits.
    await tester.tap(find.byTooltip('Send question'));
    await tester.pump();
    expect(find.text('Question'), findsOneWidget);
  });

  testWidgets('starting and stopping the mic play different tones', (
    WidgetTester tester,
  ) async {
    final voice = await pumpAssistantWithVoice(tester);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    expect(voice.cues, ['start']);

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    // Distinct tones, so the two events are not merely audible but told apart.
    expect(voice.cues, ['start', 'stop']);
  });

  testWidgets('the recogniser stopping on its own also plays the stop tone', (
    WidgetTester tester,
  ) async {
    final voice = await pumpAssistantWithVoice(tester);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();

    // A silence timeout is still a stop, and the user needs to hear it.
    await voice.stopListening();
    await tester.pump();

    expect(voice.cues, ['start', 'stop']);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });

  testWidgets('the mic button looks different while listening', (
    WidgetTester tester,
  ) async {
    await pumpAssistantWithVoice(tester);

    // Idle: outline icon, no fill.
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();

    // Listening: solid icon, and the button reports its toggled state so the
    // change is not carried by colour alone.
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(find.bySemanticsLabel('Stop dictating'), findsOneWidget);

    // The pulse is animating, so frames keep being produced.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });

  testWidgets('partial transcripts keep replacing the pending text', (
    WidgetTester tester,
  ) async {
    final voice = await pumpAssistantWithVoice(tester);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();

    voice.emit('what does');
    await tester.pump();
    voice.emit('what does the Quran say');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'what does the Quran say',
    );
    expect(find.text('Question'), findsNothing);
  });

  testWidgets('the off-device notice gates the first recording', (
    WidgetTester tester,
  ) async {
    final voice = await pumpAssistantWithVoice(tester, noticeAccepted: false);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();

    // The notice must come before the microphone opens, not after.
    expect(find.text('Before you speak'), findsOneWidget);
    expect(find.textContaining('sent off this device'), findsOneWidget);
    expect(voice.listening, isFalse);

    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(voice.listening, isFalse, reason: 'declining must not start the mic');

    // Declining is not remembered as consent: the notice returns.
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    expect(find.text('Before you speak'), findsOneWidget);

    await tester.tap(find.text('Use the microphone'));
    await tester.pump();
    expect(voice.listening, isTrue);
  });

  testWidgets('the microphone is hidden where speech is unsupported', (
    WidgetTester tester,
  ) async {
    await pumpAssistantWithVoice(tester, available: false);

    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
    // Typing still works, so the tab is not degraded.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('there is nothing to read aloud before an answer arrives', (
    WidgetTester tester,
  ) async {
    await pumpAssistantWithVoice(tester);

    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  group('recitation url templates', () {
    test('a relative path resolves against the verses CDN', () {
      expect(
        audioTemplateFromApiPath('Alafasy/mp3/002255.mp3'),
        'https://verses.quran.com/Alafasy/mp3/$kRefPlaceholder.mp3',
      );
    });

    test('a protocol-relative mirror URL is kept absolute and https', () {
      // Three of the twelve reciters answer with this shape instead.
      expect(
        audioTemplateFromApiPath(
          '//mirrors.quranicaudio.com/everyayah/Husary_64kbps/002255.mp3',
        ),
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/'
            '$kRefPlaceholder.mp3',
      );
    });

    test('a reciter folder containing digits is not mistaken for the verse', () {
      // Husary_64kbps has digits in it, but only a six-digit run is the token,
      // and only the last one.
      final template = audioTemplateFromApiPath(
        '//mirrors.quranicaudio.com/everyayah/Husary_64kbps/002255.mp3',
      )!;
      expect(template.contains('64kbps'), isTrue);
      expect(template.contains('002255'), isFalse);
    });

    test('nested paths keep their style segment', () {
      expect(
        audioTemplateFromApiPath('AbdulBaset/Mujawwad/mp3/001001.mp3'),
        'https://verses.quran.com/AbdulBaset/Mujawwad/mp3/$kRefPlaceholder.mp3',
      );
    });

    test('a path with no verse token is rejected rather than guessed', () {
      expect(audioTemplateFromApiPath('Alafasy/mp3/index.html'), isNull);
      expect(audioTemplateFromApiPath(''), isNull);
    });

    test('the template builds the right url for any ayah', () {
      const source = RecitationSource(
        reciter: Reciter(id: 7, name: 'Alafasy'),
        template: 'https://verses.quran.com/Alafasy/mp3/$kRefPlaceholder.mp3',
      );
      expect(
        source.urlFor(2, 255),
        'https://verses.quran.com/Alafasy/mp3/002255.mp3',
      );
      // Zero padding on both halves, which the filenames require.
      expect(
        source.urlFor(1, 1),
        'https://verses.quran.com/Alafasy/mp3/001001.mp3',
      );
      expect(
        source.urlFor(114, 6),
        'https://verses.quran.com/Alafasy/mp3/114006.mp3',
      );
    });

    test('verse tokens are zero padded to three digits each', () {
      expect(verseToken(1, 1), '001001');
      expect(verseToken(2, 286), '002286');
      expect(verseToken(114, 6), '114006');
    });
  });

  group('recitation host allowlist', () {
    test('accepts the Quran.com CDNs and rejects the EveryAyah mirror', () {
      expect(
        isAllowedAudioUrl('https://verses.quran.com/Alafasy/mp3/002255.mp3'),
        isTrue,
      );
      expect(
        isAllowedAudioUrl('https://audio.qurancdn.com/Alafasy/mp3/002255.mp3'),
        isTrue,
      );
      // EveryAyah publishes no terms for its audio, so it is not streamed from
      // even when Quran.com's own API points there.
      expect(
        isAllowedAudioUrl(
          'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/002255.mp3',
        ),
        isFalse,
      );
      expect(isAllowedAudioUrl('https://everyayah.com/data/x/002255.mp3'), isFalse);
      expect(isAllowedAudioUrl('not a url'), isFalse);
      expect(isAllowedAudioUrl(''), isFalse);
    });

    testWidgets('reciters served from a disallowed host are not offered', (
      tester,
    ) async {
      // Mirrors the real API: most reciters resolve to verses.quran.com, a few
      // to the EveryAyah mirror.
      final client = MockClient((request) async {
        if (request.url.path.contains('resources/recitations')) {
          return http.Response(
            jsonEncode({
              'recitations': [
                {'id': 7, 'reciter_name': 'Alafasy', 'style': null},
                {'id': 6, 'reciter_name': 'Al-Husary', 'style': null},
                {'id': 2, 'reciter_name': 'AbdulBaset', 'style': 'Murattal'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final id = int.parse(request.url.pathSegments[
            request.url.pathSegments.indexOf('recitations') + 1]);
        final url = id == 6
            ? '//mirrors.quranicaudio.com/everyayah/Husary_64kbps/001001.mp3'
            : 'Alafasy/mp3/001001.mp3';
        return http.Response(
          jsonEncode({
            'audio_files': [
              {'verse_key': '1:1', 'url': url},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = PlatformRecitationService(client: client);
      final reciters = await service.loadReciters();

      expect(reciters.map((r) => r.id), [7, 2]);
      expect(
        reciters.any((r) => r.id == 6),
        isFalse,
        reason: 'the mirror-hosted reciter must not be offered',
      );
      // And it cannot be reached by asking for it directly either.
      expect(
        await service.resolveSource(const Reciter(id: 6, name: 'Al-Husary')),
        isNull,
      );
    });
  });

  group('verse by verse recitation', () {
    Future<FakeRecitationService> openReader(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      QuranDataLoader.seedCorpusForTests(_fakeCorpus(verses: 20));
      final audio = FakeRecitationService();
      final container = ProviderContainer(
        overrides: [recitationServiceProvider.overrideWithValue(audio)],
      );
      addTearDown(container.dispose);

      final surahs = await QuranDataLoader.loadSurahs();
      await container
          .read(reciterProvider.notifier)
          .restore(await audio.loadReciters());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ReaderPage(surah: surahs.firstWhere((s) => s.number == 2)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return audio;
    }

    testWidgets('tapping play queues the whole surah from that verse', (
      tester,
    ) async {
      final audio = await openReader(tester);

      await tester.tap(find.byIcon(Icons.play_circle_outline).first);
      await tester.pump();

      expect(audio.playing, isTrue);
      // The queue covers the surah, not just the tapped ayah, so playback
      // continues without a further gesture the browser would block.
      expect(audio.requestedUrls.length, 20);
      expect(audio.requestedUrls.first, endsWith('002001.mp3'));
      expect(audio.requestedUrls.last, endsWith('002020.mp3'));
    });

    testWidgets('the reciting verse is marked and tapping again stops', (
      tester,
    ) async {
      final audio = await openReader(tester);

      await tester.tap(find.byIcon(Icons.play_circle_outline).first);
      await tester.pump();

      // The playing row swaps to a stop control; the others stay as play.
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      expect(find.byTooltip('Stop reciting'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();

      expect(audio.stopCalls, greaterThan(0));
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    });

    testWidgets('the highlight follows the queue as it advances', (
      tester,
    ) async {
      final audio = await openReader(tester);

      await tester.tap(find.byIcon(Icons.play_circle_outline).first);
      await tester.pump();
      expect(find.byTooltip('Stop reciting'), findsOneWidget);

      // Only one verse is ever marked as reciting, including after advancing.
      audio.advanceTo(3);
      await tester.pump();
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      audio.finish();
      await tester.pump();
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    });

    testWidgets('recitation records the read position as it moves', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      QuranDataLoader.seedCorpusForTests(_fakeCorpus(verses: 20));
      final audio = FakeRecitationService();
      final container = ProviderContainer(
        overrides: [recitationServiceProvider.overrideWithValue(audio)],
      );
      addTearDown(container.dispose);

      final surahs = await QuranDataLoader.loadSurahs();
      await container
          .read(reciterProvider.notifier)
          .restore(await audio.loadReciters());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ReaderPage(surah: surahs.firstWhere((s) => s.number == 2)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_circle_outline).first);
      await tester.pump();
      audio.advanceTo(7);
      await tester.pump();

      // Listening is reading: resume should return to where the audio got to.
      expect(container.read(lastReadProvider)?.ayahNumber, 7);
    });
  });

  group('assistant reference chips', () {
    /// Drive the assistant with scripted backend replies.
    Future<void> ask(
      WidgetTester tester, {
      required Map<String, dynamic> plan,
      required Map<String, dynamic> answer,
    }) async {
      SharedPreferences.setMockInitialValues({'voice_notice_accepted': true});
      final client = MockClient((request) async {
        final body = request.url.path.endsWith('/plan') ? plan : answer;
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final container = ProviderContainer(
        overrides: [httpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const QuranStudyApp(),
        ),
      );
      container.read(selectedTabProvider.notifier).state = kAssistantTabIndex;
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'test question');
      await tester.tap(find.byTooltip('Send question'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('a decline shows no chips at all', (tester) async {
      await ask(
        tester,
        // Retrieval found verses, but none of them support an answer.
        plan: {
          'status': 'ok',
          'references': ['16:68', '16:69', '2:1', '2:2', '2:3'],
          'verses': [],
          'answer': '',
        },
        answer: {
          'status': 'no_source',
          'answer': 'The verses I have do not answer this question.',
          'references': ['16:68', '16:69', '2:1', '2:2', '2:3'],
          'citations': <String>[],
        },
      );

      expect(
        find.textContaining('do not answer this question'),
        findsOneWidget,
      );
      expect(find.text('Cited verses'), findsNothing);
      // Offering retrieved verses under a decline would claim support the
      // answer explicitly says it does not have.
      for (final reference in ['16:68', '16:69', '2:1', '2:2', '2:3']) {
        expect(
          find.widgetWithText(ActionChip, reference),
          findsNothing,
          reason: 'a decline must not show $reference as a source',
        );
      }
    });

    testWidgets('an answer shows only the verses it cited', (tester) async {
      await ask(
        tester,
        plan: {
          'status': 'ok',
          'references': ['16:68', '16:69', '16:80', '16:5', '16:66'],
          'verses': [],
          'answer': '',
        },
        answer: {
          'status': 'ok',
          'answer': 'Bees are described in 16:68.',
          'references': ['16:68', '16:69', '16:80', '16:5', '16:66'],
          'citations': ['16:68'],
        },
      );

      expect(find.text('Cited verses'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '16:68'), findsOneWidget);
      // The other four were retrieved but not used, so they are not sources.
      for (final reference in ['16:69', '16:80', '16:5', '16:66']) {
        expect(
          find.widgetWithText(ActionChip, reference),
          findsNothing,
          reason: '$reference was retrieved but not cited',
        );
      }
    });

    testWidgets('a refusal shows no chips, even if the plan sends references', (
      tester,
    ) async {
      await ask(
        tester,
        // The backend sends no references with a terminal status today, but the
        // UI must not depend on that: a decline showing chips is the bug, so it
        // is pinned here rather than left to the server's good behaviour.
        plan: {
          'status': 'refused_ruling',
          'references': ['2:1', '2:2'],
          'verses': [],
          'answer': 'This is a question about religious rulings...',
        },
        answer: {'status': 'refused_ruling', 'citations': <String>[]},
      );

      expect(find.textContaining('This is a question about'), findsOneWidget);
      expect(find.text('Cited verses'), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
    });
  });

  group('surah search', () {
    // Transliterations exactly as Tanzil supplies them, which is the point:
    // they double long vowels, so a plain substring match misses the
    // spellings people type. Arabic names are left empty rather than typed out.
    SurahSummary surah(int number, String english, String transliterated) =>
        SurahSummary(
          number: number,
          nameArabic: '',
          nameSimple: english,
          nameTransliterated: transliterated,
          revelationPlace: 'makkah',
          verseCount: 7,
        );

    final fatiha = surah(1, 'The Opening', 'Al-Faatiha');
    final baqara = surah(2, 'The Cow', 'Al-Baqara');
    final yaseen = surah(36, 'Yaseen', 'Yaseen');
    final ikhlas = surah(112, 'Sincerity', 'Al-Ikhlaas');
    final nas = surah(114, 'Mankind', 'An-Naas');

    test('matches the transliterations people actually type', () {
      expect(surahMatchesQuery(baqara, 'baqara'), isTrue);
      // These three fail a plain substring match against the doubled vowels.
      expect(surahMatchesQuery(fatiha, 'fatiha'), isTrue);
      expect(surahMatchesQuery(ikhlas, 'ikhlas'), isTrue);
      expect(surahMatchesQuery(nas, 'nas'), isTrue);
      expect(surahMatchesQuery(yaseen, 'yaseen'), isTrue);
    });

    test('still matches the English meaning, number and revelation place', () {
      expect(surahMatchesQuery(baqara, 'cow'), isTrue);
      expect(surahMatchesQuery(nas, 'Mankind'), isTrue);
      expect(surahMatchesQuery(yaseen, '36'), isTrue);
      expect(surahMatchesQuery(fatiha, 'makkah'), isTrue);
    });

    test('does not match unrelated queries', () {
      expect(surahMatchesQuery(baqara, 'fatiha'), isFalse);
      expect(surahMatchesQuery(fatiha, 'baqara'), isFalse);
      expect(surahMatchesQuery(ikhlas, 'zzzz'), isFalse);
      expect(surahMatchesQuery(nas, 'madinah'), isFalse);
    });

    test('an empty query matches everything', () {
      expect(surahMatchesQuery(baqara, ''), isTrue);
      expect(surahMatchesQuery(baqara, '   '), isTrue);
    });
  });

  testWidgets('typing a transliteration filters the surah list', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    QuranDataLoader.seedCorpusForTests({
      'surahs': [
        {
          'number': 1,
          'name_arabic': '',
          'name_simple': 'The Opening',
          'name_transliterated': 'Al-Faatiha',
          'revelation_place': 'makkah',
          'verse_count': 1,
          'ayahs': [
            {'verse_number': 1, 'text': 'placeholder', 'translation': 'x'},
          ],
        },
        {
          'number': 2,
          'name_arabic': '',
          'name_simple': 'The Cow',
          'name_transliterated': 'Al-Baqara',
          'revelation_place': 'madinah',
          'verse_count': 1,
          'ayahs': [
            {'verse_number': 1, 'text': 'placeholder', 'translation': 'x'},
          ],
        },
      ],
    });

    await tester.pumpWidget(const ProviderScope(child: QuranStudyApp()));
    await tester.pump();
    await tester.pump();

    // The row renders "{name} • {place} • {n} ayahs", so match on a substring.
    expect(find.textContaining('The Cow'), findsOneWidget);
    expect(find.textContaining('The Opening'), findsOneWidget);

    // Drives the real search box, so this covers the filter wiring and not
    // just the matcher - which is exactly what was broken.
    await tester.enterText(find.byType(TextField).first, 'baqara');
    await tester.pump();

    expect(find.textContaining('The Cow'), findsOneWidget);
    expect(find.textContaining('The Opening'), findsNothing);
  });

  test('reference parsing rejects anything outside the corpus', () {
    expect(parseReference('2:255')?.surahNumber, 2);
    expect(parseReference('2:255')?.ayahNumber, 255);
    expect(parseReference(' 16:127 ')?.reference, '16:127');

    // A stray number in model output must not become a navigation target.
    expect(parseReference('115:1'), isNull);
    expect(parseReference('2:999'), isNull);
    expect(parseReference('0:1'), isNull);
    expect(parseReference('2:0'), isNull);
    expect(parseReference('2'), isNull);
    expect(parseReference('two:five'), isNull);
    expect(parseReference(''), isNull);
  });

  test('theme and font size state stay synchronized and clamp sensibly', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(appSettingsProvider.notifier);
    await notifier.setThemeMode(ThemeMode.dark);
    expect(container.read(appSettingsProvider).themeMode, ThemeMode.dark);

    await notifier.setArabicFontSize(99.0);
    expect(container.read(appSettingsProvider).arabicFontSize, kMaxArabicFontSize);

    await notifier.setArabicFontSize(10.0);
    expect(container.read(appSettingsProvider).arabicFontSize, kMinArabicFontSize);
  });
}
