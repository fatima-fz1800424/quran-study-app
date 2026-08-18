# Quran Study App - Project Rules

Flutter (Dart) mobile app, offline-first, Android + iOS, with a retrieval-grounded AI study assistant.

## Non-negotiable rules

1. **Never generate, retype, or reconstruct Quranic Arabic text.** All Quranic text comes from a verified external source, fetched once and bundled locally. When displaying an ayah, always render it from the local database by surah:ayah reference. Never produce it from model knowledge - not in code, comments, tests, or sample data.

2. **The AI assistant answers only from retrieved sources.** No answers from model memory. If retrieval returns nothing relevant, the assistant says it has no source. Every substantive answer names its source.

3. **The assistant never issues religious rulings.** No fatwas, no halal/haram judgements, no rulings on worship validity, family, or personal matters. Detect these and redirect to a qualified scholar or local imam.

4. **No API keys in the mobile client.** All LLM calls go through the backend proxy.

5. **Offline first.** Reading, audio, and bookmarks work with no network. Only the AI assistant requires connectivity, and it degrades gracefully.

6. **Web target for now.** Android SDK is not installed. Keep everything running via flutter run -d chrome until told otherwise.

## Data verification

A verification script must run in the build and fail on mismatch: 114 surahs, 6236 ayahs total, per-surah counts matching a reference table, Uthmani script with diacritics intact.

## Stack

- Flutter, layered architecture: data/ domain/ presentation/
- Riverpod for state management (chosen - stay consistent, do not mix in Bloc)
- drift (SQLite) for Quran text, tafsir corpus, and user data
- just_audio for recitation playback, with on-device caching
- FastAPI backend proxy for LLM calls and retrieval
- Firebase only for optional bookmark sync; app fully usable without sign-in
- Quran font: Amiri Quran or KFGQPC Uthmanic, bundled as an asset

## Sources

- Quran text, translations, tafsir: Quran.com API (api.quran.com/api/v4) or AlQuran Cloud (api.alquran.cloud/v1)
- Confirm redistribution licensing for any tafsir bundled into the app before building on it. Record the licence in docs/SOURCES.md.

## Working style

- Work in the staged order in docs/BRIEF.md. Stop after each stage for review.
- Ask before assuming scope. Do not add features not in the brief.
- Write tests as you go: widget tests for the reader, unit tests for the data layer, and tests asserting the assistant refuses out-of-scope fiqh questions.
- Commit at the end of each stage with a clear message.
