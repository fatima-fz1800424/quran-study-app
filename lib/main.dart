import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'surah_list_page.dart';

const double kMinArabicFontSize = 20.0;
const double kMaxArabicFontSize = 48.0;

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.arabicFontSize,
  });

  final ThemeMode themeMode;
  final double arabicFontSize;

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? arabicFontSize,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      arabicFontSize: arabicFontSize ?? this.arabicFontSize,
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier()
      : super(const AppSettings(themeMode: ThemeMode.light, arabicFontSize: 32)) {
    _load();
  }

  static const String _themeKey = 'app_theme_mode';
  static const String _fontSizeKey = 'app_arabic_font_size';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedTheme = prefs.getString(_themeKey) ?? 'light';
    final storedFontSize = prefs.getDouble(_fontSizeKey) ?? 32.0;

    state = AppSettings(
      themeMode: storedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light,
      arabicFontSize: storedFontSize.clamp(kMinArabicFontSize, kMaxArabicFontSize),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setArabicFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    final safe = value.clamp(kMinArabicFontSize, kMaxArabicFontSize);
    await prefs.setDouble(_fontSizeKey, safe);
    state = state.copyWith(arabicFontSize: safe);
  }
}

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(),
);

void main() {
  runApp(const ProviderScope(child: QuranStudyApp()));
}

class QuranStudyApp extends ConsumerWidget {
  const QuranStudyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp(
      title: 'Quran Study App',
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const SurahListPage(),
    );
  }
}
