# Project Decisions

## Source selection

- Source: Quran.com API v4
- Independent chapter-count endpoint: `https://api.quran.com/api/v4/chapters?language=en`
- Uthmani Arabic text endpoint: `https://api.quran.com/api/v4/quran/verses/uthmani?chapter_number={chapter_number}`
- Edition identifier: `quran-uthmani`
- Edition name: `Uthmani`
- Fetched on: `2026-08-19`
- Reason: These are the exact endpoints used to validate the local corpus: the chapters endpoint provides the independent per-surah ayah counts, and the Uthmani verses endpoint provides the verified Arabic text for each ayah.

## English translation candidate status

- Candidate translation: Tanzil Project, English translation `Name: Yusuf Ali`, `Translator: Abdullah Yusuf Ali`, `Language: English`, `ID: en.yusufali`, `Last Update: May 10, 2013`, `Source: Tanzil.net`.
- Licence status: explicit licence is available from Tanzil; the text is distributed under the Tanzil Project terms and the public `https://tanzil.net/trans/en.yusufali?type=xml` file contains the exact header block below:

  ```text
  # --------------------------------------------------------------------
  #
  #  Quran Translation
  #  Name: Yusuf Ali
  #  Translator: Abdullah Yusuf Ali
  #  Language: English
  #  ID: en.yusufali
  #  Last Update: May 10, 2013
  #  Source: Tanzil.net
  #
  # --------------------------------------------------------------------
  ```

- Authorisation: the Tanzil Project granted the required permission in the public terms for the Quran text and translation files by indicating that the text can be used in a website or application if the Tanzil Project is clearly indicated and a link to tanzil.net is included, and we are obeying the verbatim-copy requirement and attribution requirement. We are using one translation only, so the additional “more than three translations” link-back requirement is not triggered, but we still include attribution in-app.

## Data import strategy

- Import runs as a standalone Dart script under `tool/`.
- The imported SQL database is committed into the repo as a reviewable asset so the corpus is reproducible and not fetched at app runtime or on first launch.
- The manifest file records the imported corpus metadata and its total character count for drift detection across later runs, but it does not validate the initial fetch. The initial import is validated by comparing the independently fetched chapter counts to the imported ayah rows.
- Build-time verification checks the committed SQLite file, the total ayah count, the per-surah counts against the independent chapter endpoint, the Arabic diacritic requirements, the absence of Latin letters, and the recorded corpus character count.

## Stage 5 scope decision

- Scope choice: the assistant should use the Yusuf Ali translation already bundled in `assets/quran_reader_data.json` as the app corpus. Tafsir is out of scope for this release.
- Reason: no tafsir source with a clear redistribution licence could be identified and verified in time, so tafsir is deferred rather than bundled without a defensible rights basis. The app remains retrieval-grounded for the assistant, but the corpus is the bundled translation corpus and not classical tafsir.
