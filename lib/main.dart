import 'package:flutter/material.dart';

import 'surah_list_page.dart';

void main() {
  runApp(const QuranStudyApp());
}

class QuranStudyApp extends StatelessWidget {
  const QuranStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quran Study App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const SurahListPage(),
    );
  }
}
