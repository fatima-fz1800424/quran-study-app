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

    final light = ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFFF5F0E8),
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF7B5E47),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFFB89269),
        onSecondary: Color(0xFFFFFFFF),
        surface: Color(0xFFF9F5F0),
        onSurface: Color(0xFF201D1A),
        surfaceContainerHighest: Color(0xFFEDE3D8),
        onSurfaceVariant: Color(0xFF5E564E),
        outline: Color(0xFFD8C9B9),
        error: Color(0xFFB3261E),
        onError: Color(0xFFFFFFFF),
        tertiary: Color(0xFF6D7A5A),
        onTertiary: Color(0xFFFFFFFF),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Color(0xFFF5F0E8),
        foregroundColor: Color(0xFF201D1A),
      ),
      dividerColor: const Color(0xFFE0D3C4),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEDE3D8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: const BorderSide(color: Color(0xFFD8C9B9)),
        labelStyle: const TextStyle(color: Color(0xFF201D1A), fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8F3EE),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD8C9B9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD8C9B9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF7B5E47)),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 15, height: 1.5),
      ),
    );

    final dark = ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFF1D1C1A),
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFB89269),
        onPrimary: Color(0xFF1D1C1A),
        secondary: Color(0xFFD1B18A),
        onSecondary: Color(0xFF1D1C1A),
        surface: Color(0xFF242220),
        onSurface: Color(0xFFEFE8E1),
        surfaceContainerHighest: Color(0xFF2E2A27),
        onSurfaceVariant: Color(0xFFCBC1B5),
        outline: Color(0xFF564E48),
        error: Color(0xFFCF6679),
        onError: Color(0xFF1D1C1A),
        tertiary: Color(0xFF8FA07C),
        onTertiary: Color(0xFF1D1C1A),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Color(0xFF1D1C1A),
        foregroundColor: Color(0xFFEFE8E1),
      ),
      dividerColor: const Color(0xFF3A3531),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2D2926),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: const BorderSide(color: Color(0xFF4E4842)),
        labelStyle: const TextStyle(color: Color(0xFFEFE8E1), fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF282422),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4E4842)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4E4842)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFB89269)),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 15, height: 1.5),
      ),
    );

    return MaterialApp(
      title: 'Quran Study App',
      themeMode: settings.themeMode,
      theme: light,
      darkTheme: dark,
      home: const MainShell(),
    );
  }
}
