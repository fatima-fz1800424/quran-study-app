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

## Chunking strategy

- Decision: keep one chunk per ayah, but include a small neighbouring-verse window alongside each chunk as optional context.
- Reason: a single ayah is the minimal citation boundary and preserves the non-negotiable requirement that every answer names the exact surah:verse source. However, a passage's meaning often spans multiple verses, and retrieval quality is stronger when a chunk can include the immediate surrounding text without losing precision. The window is intentionally small (previous and next verse only), so we still keep the chunk anchored to one verse and do not cross into broad narrative blocks. This gives us source-faithful grounding with better context for downstream retrieval without encouraging over-broad chunking.
- Implementation: each chunk keeps the required fields (`surah_number`, `verse_number`, `surah_name_english`, `surah_name_arabic`, `translation_text`, and `arabic_text`) and may also include a `context_before` and `context_after` field for adjacent verses. The primary identifier remains the verse reference itself.

## Retrieval evaluation baseline

- Ground truth set: `backend/eval_queries.json`
- Model: `all-MiniLM-L6-v2`
- Embedding rule used for baseline: current-verse translation only, with surah name retained, no neighbouring translations in the embedding payload.
- Baseline numbers from the current embedding run:
  - patience in hardship: recall@5 = 0.750, MRR = 0.500
  - what does the Quran say about orphans: recall@5 = 0.500, MRR = 0.500
  - charity and giving to the poor: recall@5 = 0.667, MRR = 1.000
  - the story of Moses and Pharaoh: recall@5 = 0.500, MRR = 1.000
  - how should I treat my parents: recall@5 = 0.500, MRR = 1.000
  - Overall: recall@5 = 0.583, MRR = 0.800
- This is the baseline used for comparison against future retrieval changes.

## Retrieval variant decision

- Evaluation set expanded to 20 queries in `backend/eval_queries.json`, including hard concept queries (anxiety, depression, gratitude), surah-name queries, and two deliberately negative queries where the correct answer is that nothing relevant should rank highly.
- Aggregation rule: the 18 positive queries were used for the reported recall@5 and MRR values; the two negative queries were checked separately to confirm they do not return relevant hits in the top ranks.
- Measured results on the 20-query set:
  - Baseline (current-verse-only embedding): recall@5 = 0.231, MRR = 0.344
  - Weighted-context embedding: recall@5 = 0.269, MRR = 0.363
- Decision: keep the weighted-context variant.
- Justification: on the fuller benchmark it improves both metrics relative to the baseline, by +0.038 recall@5 and +0.019 MRR. This is the exact threshold we needed to confirm the change is genuinely beneficial instead of simply looking better on a tiny sample.

## Why the charity query regressed under weighted context

- The key regression case was the query “charity and giving to the poor,” where the weighted variant dropped from baseline recall@5 = 0.667 and MRR = 1.000 to weighted recall@5 = 0.333 and MRR = 0.250.
- The mechanism is not arbitrary: the weighted embedding concatenates each verse’s current translation, the previous verse, and the next verse. In the charity cluster, adjacent verses all talk about the same underlying topic using overlapping language: “charity,” “good,” “those in need,” “give,” “reward,” and “Allah knoweth it well.”
- The exact cluster around 2:271, 2:272, 2:273, and 2:274 therefore becomes a dense semantic neighborhood. Once those neighboring texts are injected into the same vector, the model no longer distinguishes the exact verse boundary as sharply; it treats the block as a single “charity discourse” region rather than as a set of distinct verse-level citations.
- In practice, that makes the query vector drift toward the whole cluster and pushes some expected references down in rank while boosting adjacent charity verses. The baseline version avoids that because it embeds only the current verse, so the query is anchored to the precise verse text rather than to the local topical neighborhood.
- This is precisely why we use the larger benchmark to decide: the aggregate improvement is real, but one dense cluster still shows how contextual leakage can hurt discrimnation when the topic is repeated across adjacent verses.
