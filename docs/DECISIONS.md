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

- Evaluation set expanded to 17 queries in `backend/eval_queries.json`, including hard concept queries (anxiety, depression, gratitude), surah-name queries, and two deliberately negative queries where the correct answer is that nothing relevant should rank highly.
- Aggregation rule: the 15 positive queries were used for the reported recall@5 and MRR values; the two negative queries were checked separately to confirm they do not return relevant hits in the top ranks.
- Correction (2026-08-20): this section previously said 20 queries and 18 positive. Both were wrong. `eval_queries.json` has only ever been committed with 17 keys, 15 of which carry `expected_refs`, and `run_variant_sweep.py` divides by the count of queries that have expected refs. The metrics below were therefore always computed over 15 positive queries. Re-running the sweep on 2026-08-20 reproduced every figure exactly, so the numbers stand and only the counts were mis-stated.
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

## Latest retrieval variant sweep (2026-08-19)

- Evaluation set: `backend/eval_queries.json` (15 positive queries used for aggregate metrics; see the correction note above)
- Re-run on 2026-08-20 against the same file reproduced all six variants' recall@5 and MRR to three decimal places, and the same bees top-5 per variant.
- Variants tested and measured results:
  - `dense_default` (all-MiniLM-L6-v2): recall@5 = 0.261, MRR = 0.391
  - `rerank` (all-MiniLM-L6-v2 + CrossEncoder rerank): recall@5 = 0.294, MRR = 0.406
  - `hybrid` (dense+BM25 fusion): recall@5 = 0.167, MRR = 0.283
  - `mpnet` (all-mpnet-base-v2 dense): recall@5 = 0.356, MRR = 0.444
  - `mpnet_rerank` (all-mpnet-base-v2 initial retrieval + CrossEncoder rerank): recall@5 = 0.278, MRR = 0.452
  - `threshold` (dense with score cutoff): recall@5 = 0.261, MRR = 0.391

- Bees query (`what does the Quran say about bees`) top-5 per variant:
  - `dense_default`: ['16:128', '16:74', '16:53', '16:32', '16:83']
  - `rerank`: ['16:68', '16:80', '16:83', '16:87', '16:98']
  - `hybrid`: ['16:81', '16:32', '16:98', '16:109', '16:83']
  - `mpnet`: ['16:48', '16:89', '16:74', '16:37', '16:68']
  - `mpnet_rerank`: ['16:68', '16:83', '16:87', '16:98', '16:49']
  - `threshold`: ['16:128', '16:74', '16:53', '16:32', '16:83']

Decision and action taken:

- `all-mpnet-base-v2` (`mpnet`) produced the highest aggregate recall@5 (0.356) and competitive MRR; `mpnet_rerank` gave the highest MRR but lower recall. Prioritizing recall@5 for citation recovery, we select `mpnet` as the default retrieval model for the `/ask` endpoint.
- The `/ask` endpoint has been updated to call the retriever with `model_name='sentence-transformers/all-mpnet-base-v2'` so the assistant uses the stronger mpnet embeddings by default.
- The hybrid implementation in `backend/retrieval.py` was also fixed to union dense and BM25 top candidates and normalize scores before fusion (previously it gated candidates by dense-only top-50 and that could exclude BM25-only strong matches).

Next steps recommended:

- Consider `mpnet_rerank` as a follow-up: it improves MRR and rank-1 precision for some queries (e.g., the bees case) and could be used asynchronously or as an optional higher-cost rerank stage.
- Re-run the benchmark on a larger evaluation set if available to confirm the selection beyond the current 18-query sample.

## Audio recitation: two modes, and why (2026-08-20)

Stage 3 ships two distinct playback modes rather than one. That is forced by
what the available sources actually publish, not by a UI preference.

### Verse by verse - Quran.com CDN

Per-ayah playback with verse highlighting and auto-scroll needs one audio file
per ayah. Four sources publish ayah-level files:

| Source | Reciters | Ayah-level files | Stated terms |
|--------|----------|------------------|--------------|
| Quran.com / Quran Foundation | 12 | yes | yes, quoted below |
| EveryAyah.com | 60+ | yes | **none found** |
| AlQuran Cloud | 189 editions | yes | not checked for audio |
| QuranicAudio.com | 177 qaris | whole surah | not checked |

Verified against the live API: `GET /api/v4/recitations/{id}/by_ayah/{s}:{a}`
returns a relative path such as `Alafasy/mp3/002255.mp3`, served from
`https://verses.quran.com/` and `https://audio.qurancdn.com/`, both answering
200 with `Access-Control-Allow-Origin: *` and `Accept-Ranges: bytes`. Measured
sizes run from 143KB for 1:1 to 3.97MB for 2:282 at 128kbps.

**EveryAyah is deliberately not used.** Its pages carry no copyright notice,
licence or terms for the audio. The only stated terms on the site cover the
*timing files*: "(C) VerseByVerseQuran.com You must link back to our site from
your product and web-site to use these timings", and that licence link now
404s. The widely repeated claim that its audio is CC-BY-NC traces to an outside
commenter on a GitHub issue, not to the site or any maintainer, and its Internet
Archive mirror carries no `licenseurl` or `rights` field. Absence of a
prohibition is not permission, and the recitation is a performance - separately
copyrightable from the Quran text.

Audio is streamed, never bundled. One reciter is 825MB at 64kbps and 1,629MB at
128kbps, measured from the bulk archive sizes. Storing it would also conflict
with the Quran Foundation one-week cache limit that moved the text to Tanzil.

### Full surah - mp3quran.net

Per-ayah playback cannot cover every reciter, because most sources only publish
whole-surah files. Haitham al-Dokhain is the case that forced this: he is absent
from all four ayah-level sources above, and present on mp3quran.net as reciter
id 273 with all 114 surahs, but only as whole-surah audio. Verified: `001.mp3`
is 0.9MB, `002.mp3` is 86MB, and a per-ayah path returns 404. With no ayah
boundaries there is nothing to highlight or scroll to, so this mode is a single
continuous player with no verse tracking. That is the honest presentation of
what the files support.

mp3quran.net does grant permission explicitly, which EveryAyah does not. From
https://www.mp3quran.net/eng/privacy:

> "Copyrights: All rights are available to everyone, and we allow any visitor or
> developer to copy any material or use any link on the websites"

and in Arabic on the same page:

> "الحقوق: جميع الحقوق متاحة للجميع و يحق لأي زائر أو مطور استخدام اي مادة أو
> رابط من الموقع"

**Two limits on that grant, recorded because they matter.** It is a
*redistributor's* grant: mp3quran can only pass on rights it holds, and while
they publish signed cooperation agreements with some reciters, no chain of title
for al-Dokhain specifically was verified. And it names no licence, no version,
no attribution requirement and gives no warranty - it is a broad informal
statement on a privacy page, not a terms document. It clears the bar of being an
affirmative permission rather than mere silence, which is the standard applied
here, but it is weaker evidence than a named licence would be.

## Arabic text moved from Quran.com to Tanzil (2026-08-20)

### Why

The Arabic text was bundled from the Quran.com API v4 and stored permanently in
a now-public repository. The [Quran Foundation Developer
Terms](https://api-docs.quran.foundation/legal/developer-terms/) say:

> "Cache or store QF Content longer than **1 week**, except where (a) QF has
> expressly permitted longer storage, or (b) the QF Content is available through
> the Content Sync APIs"

> "QF Content is **not resold, sublicensed, or redistributed** except as
> integral to the end-user experience of the Application."

There is no reading of that under which an offline-first app can bundle their
text indefinitely. Tanzil, already the source of the translation, permits
precisely this use:

> "Permission is granted to copy and distribute verbatim copies of the Quran
> text provided here, but changing the text is not allowed. The text can be used
> in any website or application, provided that its source (Tanzil Project) is
> clearly indicated, and a link is made to tanzil.net to enable users to keep
> track of changes."

Surah metadata also moved to Tanzil (`quran-data.js`, CC Attribution 3.0), since
names and counts from the QF endpoint were stored too. The QF chapters endpoint
is still called at build time to cross-check per-surah counts; nothing from it is
written to disk.

### The editions were compared before anything was replaced

All 6236 ayahs, both editions:

| Check | Result |
|-------|--------|
| Surahs / ayahs / per-surah counts | 114 / 6236 / 0 mismatches |
| Byte-identical ayahs, raw | 1935 / 6236 |
| Differing after removing annotation marks only | 2800 |
| Differing after also collapsing whitespace | 112 |
| **Differing after separating the basmala** | **0** |

So there is **no textual variance between the editions at all**. Every
difference was one of three presentational things: annotation marks (Tanzil's
default export omits pause marks, sajdah and rub-el-hizb signs, and tatweel -
enabling those options in the download URL reproduces them exactly), whitespace,
and the basmala.

The basmala accounts for the last 112. Tanzil's line-per-ayah format prepends it
to verse 1 of every surah that opens with one - all but surah 1, where the
basmala *is* verse 1, and surah 9, which has none. The importer separates it into
a per-surah `bismillah` field, preserving Tanzil's bytes exactly, so the corpus
still holds every character of their text. It is stored rather than displayed,
which matches the previous behaviour; rendering it as a surah header is available
whenever wanted.

One real orthographic detail surfaced while doing this: the basmala before
surahs 95 and 97 carries a **shadda on the initial ba** that the other 110 do
not, because surahs 94 and 96 both end in ba and continuous recitation
assimilates. Tanzil encodes both spellings; the importer keeps whichever it was
given rather than substituting a canonical form.

### Consequence: retrieval moved slightly

Surah English names differ between the sources for 41 surahs - "The Opener" vs
"The Opening", "Jonah" vs "Jonas", "The Rocky Tract" vs "The Rock" - and
`build_corpus.py` puts that name into `embedding_text`. So 1871 of 6236 chunks
(30%) changed, the embedding cache was invalidated, and the corpus was
re-embedded. Measured against the same labels:

| Metric | Before | After |
|--------|--------|-------|
| MRR | 0.917 | **0.917** |
| precision@5 | 0.747 | 0.693 |
| recall@5 (ceiling-aware) | 0.757 | 0.703 |
| recall@5 (as the sweep reports it) | 0.479 | 0.445 |
| relevant verses in the top 5 | 56 / 75 | 52 / 75 |
| queries with nothing relevant in the top 5 | 0 | 0 |

Four hits out of 75 lost, MRR unchanged: the first result is still relevant for
the same queries. That is the price of the licensing fix and it was accepted
rather than worked around. Two notes for anyone comparing these numbers:

- The labels were pooled from the *previous* retrieval's top 10, so verses newly
  surfaced by the changed embeddings are unlabelled and score as misses. The
  0.693 is therefore a floor, not a like-for-like reading.
- `name_simple` now holds Tanzil's English name and a `name_transliterated`
  field was added alongside it. Switching the embedded name to the
  transliteration, or embedding both, is untested and might recover the
  difference.

### Also removed

`assets/quran.sqlite`, `tool/import_quran.dart` and the `scratch/` build scripts
were deleted. The sqlite held a second copy of the QF-sourced Arabic and was
bundled into the web build although no runtime code read it; the Dart importer
would have re-created the licensing problem if run. Note that DECISIONS.md
previously described the importer as "a standalone Dart script under `tool/`" -
that built the sqlite, while the asset the app actually reads was built by an
undocumented script in `scratch/`. The single importer is now
`tool/build_quran_assets.py`.

## Relabelling the evaluation set (2026-08-20)

The original `expected_refs` were written from memory by a non-specialist and
were badly incomplete. Every query's top 10 was reviewed against the full
translation text (`docs/eval_review.md`) and the genuinely relevant verses were
added. Labelled refs went from 57 to 118 across the 15 positive queries. The two
negative queries were confirmed as correctly having nothing relevant.

Retrieval did not change. The same top 5 was scored against both label sets, so
everything below is a change in measurement.

| Metric | Old labels | New labels | Change |
|--------|-----------|------------|--------|
| recall@5 (as the benchmark defines it) | 0.356 | 0.479 | +0.124 |
| recall@5 (ceiling-aware) | 0.356 | **0.757** | +0.401 |
| precision@5 | 0.253 | **0.747** | +0.493 |
| MRR | 0.444 | **0.917** | +0.472 |
| relevant verses in the top 5 | 19 / 75 | **56 / 75** | +37 |
| queries with nothing relevant in the top 5 | 5 | **0** | -5 |

**The headline recall@5 understates this badly, and is now a broken metric.** It
divides by `len(expected_refs)`, so once a query has more than five relevant
verses the score cannot reach 1.0 - it is capped at `5/N`. Four queries actually
scored *lower* after relabelling for that reason alone: "the story of Moses and
Pharaoh" fell from 1.000 to 0.500 while all five of its top results are now
known to be relevant, i.e. precision@5 of 1.000. The ceiling-aware variant
divides by `min(N, 5)` instead, and precision@5 and MRR are unaffected by the
denominator entirely. Prefer MRR and precision@5 for future comparisons; the
sweep script still computes only the original definition.

So retrieval was substantially better than the old numbers claimed. MRR of 0.917
means the top result is relevant for almost every query. The earlier conclusion
that recall@5 of 0.356 showed weak retrieval was largely a measurement artifact.

### Variant sweep, rescored

| Variant | recall@5 old -> new | MRR old -> new |
|---------|--------------------|----------------|
| `dense_default` (MiniLM) | 0.261 -> 0.206 | 0.391 -> 0.508 |
| `rerank` | 0.294 -> 0.244 | 0.406 -> 0.536 |
| `hybrid` | 0.167 -> 0.143 | 0.283 -> 0.447 |
| `mpnet` | 0.356 -> **0.479** | 0.444 -> **0.917** |
| `mpnet_rerank` | 0.278 -> 0.290 | 0.452 -> 0.900 |
| `threshold` | 0.261 -> 0.206 | 0.391 -> 0.508 |

`mpnet` remains the choice, by a wider margin than before.

**Caveat on the cross-variant comparison.** The labels were pooled from
`mpnet`'s top 10 only, because that is the production path and what was
reviewed. Any verse that only another variant surfaces is still unlabelled and
still scores as a miss, which biases the comparison in `mpnet`'s favour. The
absolute `mpnet` figures are sound; the ranking against the other variants is
not, until candidates are pooled from every variant and the union annotated.
That is the standard pooling procedure and it was not followed here.

### Failures that relabelling did not explain away

Some queries are genuinely poorly served, and it is worth being precise about
which:

- **"responding to wrongdoing"**: of ten results only `16:90` is relevant. The
  canonical verses on repaying wrong with good - `41:34`, `16:126`, `4:148` - do
  not appear at all. Real retrieval failure.
- **Justice**: `4:135` ("stand out firmly for justice") ranks **93rd** and
  `4:58` ("when ye judge between man and man, judge with justice") ranks
  **1518th**. This was originally reported as a labelling gap; it is not. The
  retriever does not surface either verse.
- **"anxiety"**: the model conflates anxiety with *taqwa*, the fear of Allah.
  Four of the ten results (`20:3`, `26:142`, `26:177`, `6:51`) are about
  God-fearing piety, a different concept entirely. This is what happens when a
  modern psychological vocabulary is matched against a 1930s translation:
  "anxiety" and "fear" collapse together in the embedding space although the
  1934 English uses "fear" almost exclusively in the religious sense. No
  reranking fixes a vocabulary mismatch of that kind; it needs either query
  expansion or a translation in contemporary English.

### Future work, not built

- **Near-duplicate suppression.** The gratitude query spends four of its ten
  slots on `26:127`, `26:145`, `26:164` and `26:180`, which are the same
  sentence repeated in different surahs. Collapsing near-identical translations
  to one representative would free up 40% of that result list. Worth doing;
  deliberately not done now.
- Pooled multi-variant labelling, per the caveat above.

## Voice input and read-aloud (2026-08-20)

Added to the assistant tab only: a microphone that dictates into the question
field, and a speaker that reads an answer back. `speech_to_text` and
`flutter_tts`.

Two properties are deliberate and enforced by tests rather than by convention:

- **The transcript never sends itself.** Dictation only ever writes into the
  question field; sending requires the send button or the Enter key. A final
  result from the recogniser means the recogniser has stopped, not that the user
  has decided to ask - and misheard religious terms are exactly the case where
  an automatic send would be worst. The test asserts that a final,
  high-confidence transcript produces no request.
- **The off-device notice is a gate, not a footnote.** Audio leaves the device
  (see below), so the notice appears and must be accepted *before* the
  microphone is opened. Accepting is remembered; declining is not, so a decline
  can never be mistaken for consent later.

The microphone is hidden, not disabled, where the platform reports no speech
support, so it never appears as a broken control and no audio is captured on
unverified platforms.

### The offline conflict, stated plainly

Web dictation is a wrapper over the browser's Web Speech API, so **the audio of
the user's voice is sent off the device** to the browser vendor's speech
service. That is a stronger data flow than anything else in the app, and it is
recorded in `docs/SOURCES.md` alongside the Gemini flow.

It also means voice requires connectivity. That is consistent with where the
line already sits rather than a new exception: CLAUDE.md rule 5 exempts the AI
assistant, which needs the network regardless, and voice lives entirely inside
that tab. Reading, audio playback, bookmarks and settings remain fully offline.

Read-aloud is given the English answer only. Quranic Arabic is never passed to a
speech engine - an English voice mispronounces it, and rule 1 covers audio as
much as text.

## /ask latency, and why the answer is not streamed (2026-08-20)

Profiled per stage against a running server. The starting point was an 8.6s
median /ask, of which 98.7% was the model call.

| Change | /ask median | Note |
|--------|-------------|------|
| Baseline | 8270 ms | 706-858 thinking tokens per call |
| `max_output_tokens=300` + brevity prompt | 4470 ms | broken - see below |
| plus `thinking_level=MINIMAL` | 2372 / 4140 ms | 2 samples only |

Two findings worth keeping:

- **The model thinks by default, heavily.** It spent 706-858 thinking tokens
  against 121-271 output tokens, to summarise five verses handed to it in the
  prompt. `thinking_level=MINIMAL` was the single largest win.
- **`max_output_tokens` is a shared budget with thinking on this model.**
  Capping at 300 while thinking was still enabled left 9-12 tokens for the
  answer and truncated every reply to a 46-character uncited fragment. The
  citation guardrail caught all four and returned `no_source`, which is the
  system working, but the cap is only safe with thinking minimised. The
  constant in `app.py` records this so it is not re-raised in isolation.

Retrieval was also renormalising the whole 6236x768 embedding matrix on every
request to recompute a constant. Normalising once at load took /search from
113ms to 37ms median, with byte-identical `/related` results.

The `/ask` measurements above are only 2 samples at the final setting, because
profiling exhausted the API quota. Baseline variance was 6.5-17.4s, so the
final median should be re-measured before it is trusted.

### Streaming the answer was rejected

Three options were considered for making the wait feel shorter:

- (a) stream the answer text, holding it back until a verified citation appears
- (b) stream freely and retract if the citation check fails
- (c) do not stream the answer; report progress stages instead

**Chosen: (c).** (b) is unacceptable: retracting text a reader has already taken
in is worse in a religious-study context than making them wait. (a) was
rejected because it makes a safety property depend on a formatting preference -
the citation check could only stay non-blocking if the model reliably cites
early, so a prompt-level style choice would silently determine whether answers
are verified before display. At 2.4-4.1s the perceived gain did not justify
that coupling.

(a) remains available if latency regresses badly, but it would need the prompt
to mandate a leading reference, and that coupling should be recorded explicitly
if it is ever adopted.

Implementation of (c): `/ask/plan` runs the refusal check and retrieval only,
with no model call, and the client calls it before `/ask`. Measured: a refused
question comes back in 2.3ms, and the retrieved verses in 29.5ms, so the user
sees a refusal almost instantly, or reads the verses that were found while the
answer is still being written. `/ask` repeats the work rather than trusting the
client, so skipping `/ask/plan` changes nothing about the result.

Note this is not streaming transport. Flutter web's `BrowserClient` buffers a
streamed response whole, so server-sent events would have needed a new
fetch-based HTTP dependency and still delivered nothing incrementally. Two short
requests achieve the same result with no dependency.

### Model errors are rephrased before they reach the client

The client displays the backend's `detail` string directly, and a quota failure
was surfacing `429 RESOURCE_EXHAUSTED` plus the raw provider JSON to users.
Quota exhaustion now returns 503 with a readable sentence that also points out
that reading and search still work; other model failures return 502 with a
generic sentence. The full error goes to the log. Tests assert that no provider
internals appear in either message.

### `/search` will not load an arbitrary model

`search(model_name=...)` used to be silently ignored after startup, returning
results from whichever model loaded first. Honouring it correctly created a
worse problem: loading a model means downloading weights and embedding 6236
verses, roughly 15 minutes of CPU, so any caller could trigger that repeatedly.
`initialize()` now reloads properly when the requested model differs, and the
HTTP endpoint accepts only pre-benchmarked models, returning 400 otherwise.

## Assistant refusal is enforced in code (2026-08-20)

Refusal used to live only in the Gemini system prompt. A prompt fails open,
varies between calls, and cannot be tested without spending a model call, while
CLAUDE.md asks for ruling questions to be detected. `backend/guardrails.py` now
enforces refusal, a retrieval relevance floor, and citation verification in our
own process. The prompt rules stay as a second layer.

The detector has four triggers: ruling vocabulary; a religion-or-law frame
("what does Islam say about ..."); a personal modal plus an act of worship
("can I pray without wudu"); and a how-to-perform framing plus a rite ("the
proper way to baptize an infant in Islam"). The last two are conjunctions on
purpose - either half alone appears in ordinary study questions.

Questions about what *the Quran* says are deliberately never a trigger, so
thematic search keeps working.

Measured on 28 study questions and 13 ruling questions: all 13 refused, all 28
allowed. Adding the how-to trigger refused 8 more ruling questions and did not
newly refuse any study question. Of the 17 eval queries, one is now refused
before retrieval: "what is the proper way to baptize an infant in Islam", one of
the two deliberate negatives. It carries no `expected_refs`, so aggregate
metrics are unaffected - but the guardrail, not retrieval, is what now handles
it, and that query no longer exercises what it was written to exercise.

Known gap: the relevance floor does not catch in-domain but unanswerable
questions. The two designed negatives score 0.4677 and 0.3990, both above the
0.35 floor. No floor separates them from legitimate low scorers such as "how
should I treat my parents" at 0.4927. The floor filters off-domain noise; it
cannot filter plausible-sounding questions the corpus does not answer. The other
negative, "what is the best Islamic stock portfolio strategy", is still not
refused: it is financial rather than worship practice, and no narrow pattern for
it looked defensible.

## Related-verses cross-surah gate (2026-08-19)

The `/related` endpoint has to answer two different questions, and conflating
them was making it return nothing for verses that do have a good match:

1. Does this verse resonate outside its own surah at all? If not, its
   same-surah matches are almost always surah-level topical bleed - adjacent
   verses reusing the same vocabulary - rather than genuine thematic links.
2. Is a given candidate strong enough to show?

Question 2 needs a higher bar than question 1. Using one threshold for both
meant a verse could be denied its own strong match because no *other* surah
cleared the display bar. Measured on `all-mpnet-base-v2`, with
`same_surah_penalty=0.03`:

| Verse | Best cross-surah | Same-surah passing 0.70 |
|-------|------------------|-------------------------|
| 112:1 | 0.7373           | none                    |
| 18:60 | 0.6579           | 18:64 at 0.7081         |
| 16:68 | 0.6378           | 16:6, 16:15, 16:80      |
| 2:255 | 0.7969           | six, incl. 2:163        |

18:60 and 16:68 are indistinguishable under a single threshold: both have zero
cross-surah candidates above 0.70. But 18:60 does reach outside surah 18
(52:6 at 0.658) while 16:68 does not reach past 0.638 - and 18:64 is the
continuation of the same Musa and Khidr narrative, which is exactly the kind of
link the endpoint exists to surface.

Decision: separate the two thresholds.

- `cross_surah_gate_score` (default 0.65) - the verse must have at least one
  cross-surah candidate this strong, or the endpoint returns nothing.
- `min_score` (default 0.70) - what an individual result must score to be shown.
- `max_same_surah` (default 2) - caps results from the target's own surah only,
  as a hard cap.

Resulting behaviour: 112:1 and 2:255 unchanged, 18:60 returns 18:64, 16:68
stays empty.

Caveat: the design generalises, but the 0.65 constant is calibrated on these
four verses and sits in a narrow 0.638-0.658 band. It should be re-checked
against a larger reference set before it is treated as settled.

Two related bugs were fixed at the same time:

- `max_same_surah` was capping *every* surah at that count, not just the
  target's. It is documented as same-surah capping, and capping unrelated
  surahs silently dropped good cross-surah results.
- When the cap left fewer than `k` results, the code backfilled with the very
  candidates the cap had just excluded, so the cap was advisory rather than a
  cap. It is now hard: those slots go to the next best cross-surah verse or go
  unfilled.

