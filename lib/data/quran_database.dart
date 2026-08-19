/// Web-only runtime path: the app reads bundled JSON, not SQLite.
/// Native SQLite access is intentionally kept out of the web entrypoint and will
/// be added behind a platform conditional when Android is added later.
class QuranDatabase {
  static Future<void> ensureWebJsonOnly() async {
    throw UnsupportedError(
      'Web runtime must use assets/quran_reader_data.json. SQLite is intentionally unavailable here.',
    );
  }
}
