// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_study_app/main.dart';
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
