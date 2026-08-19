# Project Decisions

## Source selection

- Source: Quran.com API v4
- Independent chapter-count endpoint: `https://api.quran.com/api/v4/chapters?language=en`
- Uthmani Arabic text endpoint: `https://api.quran.com/api/v4/quran/verses/uthmani?chapter_number={chapter_number}`
- Edition identifier: `quran-uthmani`
- Edition name: `Uthmani`
- Fetched on: `2026-08-19`
- Reason: These are the exact endpoints used to validate the local corpus: the chapters endpoint provides the independent per-surah ayah counts, and the Uthmani verses endpoint provides the verified Arabic text for each ayah.

## Data import strategy

- Import runs as a standalone Dart script under `tool/`.
- The imported SQL database is committed into the repo as a reviewable asset so the corpus is reproducible and not fetched at app runtime or on first launch.
- The manifest file records the imported corpus metadata and its total character count for drift detection across later runs, but it does not validate the initial fetch. The initial import is validated by comparing the independently fetched chapter counts to the imported ayah rows.
- Build-time verification checks the committed SQLite file, the total ayah count, the per-surah counts against the independent chapter endpoint, the Arabic diacritic requirements, the absence of Latin letters, and the recorded corpus character count.
