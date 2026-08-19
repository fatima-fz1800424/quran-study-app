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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Quran app loads the surah list', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: QuranStudyApp()));

    expect(find.text('Surah List'), findsOneWidget);
    expect(find.text('Reader'), findsNothing);
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
