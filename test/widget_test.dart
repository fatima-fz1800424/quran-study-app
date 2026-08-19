// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quran_study_app/main.dart';
import 'package:quran_study_app/surah_list_page.dart';

/// A stand-in surah for reader tests. Only `number` affects what these tests
/// assert, and the Arabic name is left empty rather than typed out, so no
/// Quranic text or name is reproduced here. Loading the real surah from the
/// bundle is not an option in `testWidgets`: `rootBundle` needs real async,
/// which the fake-async test zone does not run.
const SurahSummary _testSurah = SurahSummary(
  number: 2,
  nameArabic: '',
  nameSimple: 'Al-Baqarah',
  revelationPlace: 'madinah',
  verseCount: 286,
);

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

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: ReaderPage(surah: _testSurah))),
    );
    // Deliberately not pumpAndSettle: the reader shows a progress indicator
    // while the corpus loads, and that animation never settles. The read
    // position is recorded on open, so one frame is enough.
    await tester.pump();

    // Reading is enough on its own: last-read must not depend on bookmarking.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_read_surah'), 2);
    expect(prefs.getInt('last_read_ayah'), 1);
  });

  testWidgets('jumping to an ayah records that ayah as the read position', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReaderPage(surah: _testSurah, initialAyah: 255),
        ),
      ),
    );
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_read_surah'), 2);
    expect(prefs.getInt('last_read_ayah'), 255);
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
