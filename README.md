# Quran Study App

An offline-first Quran reader with a retrieval-grounded study assistant.

The reader works with no network. The assistant does not: it needs a backend,
which holds the LLM key and answers only from verses it retrieved from the
bundled translation. It refuses religious rulings, and it refuses to answer at
all when retrieval finds nothing relevant.

Current target is **Flutter web**. Android and iOS are not built or tested yet -
the Android SDK is not installed in the development environment.

## What works today

| Feature | State |
|---------|-------|
| Surah list with search by name, number or revelation place | Working |
| Reader with Uthmani Arabic, adjustable font, optional translation | Working |
| Bookmarks, last-read resume | Working |
| Theme and font settings, persisted | Working |
| Study assistant: retrieval, refusals, citations, progress stages | Working |
| Citation chips that open the cited verse in the reader | Working |
| Voice dictation and read-aloud (assistant tab, Chrome) | Working |
| Audio recitation, verse by verse, with highlight and auto-scroll | Working |
| Reciter selection (9 Quran.com reciters) | Working |
| **Full-surah playback mode (mp3quran reciters)** | **Not built** |
| **Download-for-offline audio** | **Not built** - see limitations |
| **Juz / Hizb browsing, go-to-ayah jump** | **Not built** |
| **Firebase bookmark sync** | **Not built** |
| **Tafsir corpus** | **Out of scope** - see Data sources |

## Setup from a fresh clone

### Prerequisites

- Flutter 3.47 or later (developed on 3.47.0 stable), Dart SDK ^3.13.0
- Python 3.13
- Chrome, for the web target and for voice input

### Frontend

```bash
flutter pub get
flutter run -d chrome
```

The reader works immediately. The corpus is bundled as
`assets/quran_reader_data.json`, so nothing is fetched at runtime and no
backend is needed to read.

The assistant tab expects a backend at `http://127.0.0.1:8123`, hardcoded as
`kQuranBackendBaseUrl` in `lib/surah_list_page.dart`. Change it there if you run
the backend elsewhere.

### Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
python -m pip install --upgrade pip
pip install -r requirements.txt
uvicorn app:app --reload --host 127.0.0.1 --port 8123
```

**The first start is slow, and not by a little.** `backend/.retrieval_cache/` is
gitignored, so a fresh clone has neither the model nor the embeddings:

| First run | Cost |
|-----------|------|
| Download `all-mpnet-base-v2` | ~500MB |
| Embed all 6236 verses on CPU | ~15 minutes |
| Later starts (cache present) | ~12 seconds |

Nothing warns you while this happens beyond the log line. Budget for it.

### Environment

```bash
export GEMINI_API_KEY="your_key_here"
# Windows PowerShell:
# $env:GEMINI_API_KEY = "your_key_here"
```

`/ask` returns HTTP 500 without a key. Every other endpoint works without one.
A `.env` file in the project root is also read, and is gitignored - do not
commit a key. The key never reaches the client; that is the whole point of the
backend proxy.

### Tests

```bash
flutter test          # 45 tests
cd backend && python -m pytest   # 70 tests
```

Backend tests mock the model call, so they need no API key and no network.

## Architecture

```
Flutter web client                    FastAPI backend
------------------                    ---------------
Reader        -> bundled JSON         /ask/plan  refusal check + retrieval
Assistant     -> HTTP -------------> /ask       + Gemini, citation check
                                      /search    raw retrieval
                                      /related   related verses
                                          |
                                          v
                                      corpus.json (6236 chunks)
                                      embeddings .npy (19MB, cached)
                                      all-mpnet-base-v2
                                          |
                                          v
                                      Gemini API (key server-side only)
```

The client asks in two steps. `/ask/plan` runs the refusal check and retrieval
with no model call and returns in milliseconds, so a refused question comes back
almost instantly and the retrieved verses can be shown while the answer is still
being written. `/ask` then repeats that work rather than trusting the client, so
skipping the first call changes nothing.

The answer is deliberately **not** streamed. Streaming text would put words on
screen before the citation check could run, and that check is what keeps answers
grounded. See `docs/DECISIONS.md`.

### Assistant guardrails

Three run in our own process, not in the prompt, because a prompt fails open and
cannot be tested without spending a model call:

1. **Ruling questions never reach the model.** Detected from ruling vocabulary,
   religion-or-law framings ("what does Islam say about..."), personal modals
   about acts of worship ("can I pray without wudu"), and how-to-perform
   framings ("the proper way to..."). Measured: 13/13 ruling questions refused,
   0/28 study questions wrongly refused.
2. **A relevance floor.** Retrieval always returns its k best however weak;
   below 0.35 the assistant says it has no source instead of calling the model.
3. **Citation verification.** An answer is shown only if it cites a verse that
   was actually retrieved. Citations of unretrieved verses are dropped, and an
   answer left with none is replaced by the no-source reply.

The assistant also carries a permanent, non-dismissible notice that it is a
study tool and not a substitute for a qualified scholar.

### Layout

```
lib/
  main.dart              app shell, theme, settings state
  surah_list_page.dart   surah list, reader, assistant   (monolithic - see below)
  voice.dart             speech seam + platform implementation
  recitation.dart        recitation seam, url templates, reciter state
  data/                  corpus validation rules (shared with the importer)
backend/
  app.py                 FastAPI endpoints
  retrieval.py           embeddings, dense/hybrid/rerank search
  guardrails.py          refusal detection, relevance floor, citations
  build_corpus.py        corpus.json from the bundled asset
  run_variant_sweep.py   retrieval benchmark
tool/build_quran_assets.py  builds the bundled corpus from Tanzil, verified
docs/                    BRIEF, DECISIONS, SOURCES, eval_review
```

## Data sources and licences

Recorded in full in `docs/SOURCES.md`, including third parties that receive
user data.

| Data | Source | Licence / basis |
|------|--------|-----------------|
| Uthmani Arabic text | Tanzil Project, Uthmani edition | Tanzil terms: verbatim copies permitted in any application with attribution and a link to tanzil.net, both of which the app carries |
| Surah metadata | Tanzil Project `quran-data.js` | Creative Commons Attribution 3.0 |
| English translation | Tanzil Project, Yusuf Ali (`en.yusufali`) | Same Tanzil terms |
| Per-surah ayah counts | Quran.com API v4 chapters endpoint | Build-time cross-check only; nothing from it is stored, as their terms cap storage at one week |
| Tafsir | none | **Deliberately excluded** - no source with a clear redistribution licence could be verified, so tafsir was dropped rather than shipped without a rights basis |

Quranic Arabic is never generated, retyped or reconstructed anywhere in this
repo - not in code, tests or fixtures. It is rendered only from the verified
local corpus by surah:verse. Test fixtures use placeholder Latin text for that
reason. A verification script checks 114 surahs, 6236 ayahs, per-surah counts
against the independent chapter endpoint, and that diacritics are intact.

## Known limitations

Read this section before trusting the assistant for anything.

### Retrieval quality

Measured on 15 labelled queries in `backend/eval_queries.json`, using
`all-mpnet-base-v2`:

| Metric | Value |
|--------|-------|
| **MRR** | **0.917** |
| **precision@5** | **0.693** |
| relevant verses in the top 5 | 52 / 75 |
| recall@5 as the sweep script reports it | 0.445 |

**Do not read that recall@5 as the headline.** It divides by the number of
labelled relevant verses, so a query with more than five of them cannot score
1.0 no matter how good the ranking is - it is capped at `5/N`. When the labels
were corrected, four queries' recall@5 went *down* while their results got
demonstrably better: "the story of Moses and Pharaoh" dropped from 1.000 to
0.500 at the same time as its precision@5 reached 1.000. MRR and precision@5 do
not depend on that denominator and are the numbers to use.

The labels themselves were originally written from memory and were wrong. After
review, MRR went from 0.444 to 0.917 with **no change to retrieval at all** -
the old figures were measuring bad labels. Two caveats on the current ones:

- They were pooled from `mpnet`'s top 10 only, which biases the comparison
  between retrieval variants in `mpnet`'s favour. Its absolute numbers are
  sound; the cross-variant ranking is not.
- 15 queries is a small benchmark. Treat differences of a few points as noise.

### Specific retrieval failures

- **Justice.** `4:58` ("when ye judge between man and man, judge with justice")
  ranks **1518th** for "what does the Quran say about justice". `4:135` ranks
  93rd. Two of the most central justice verses in the Quran are not retrievable
  by that query.
- **"Responding to wrongdoing."** One relevant verse in ten results. `41:34`,
  `16:126` and `4:148` do not appear.
- **Anxiety collapses into taqwa.** Asking about anxiety returns verses about
  the fear of Allah - `20:3`, `26:142`, `26:177`, `6:51`. The Yusuf Ali
  translation dates from the 1930s and uses "fear" almost exclusively in its
  religious sense, so modern psychological vocabulary lands on the wrong
  concept. Reranking cannot fix a vocabulary mismatch; it needs query expansion
  or a contemporary translation.
- **Near-duplicate crowding.** The gratitude query spends four of ten slots on
  `26:127`, `26:145`, `26:164` and `26:180` - the same sentence repeated across
  surahs.

### Assistant behaviour

- The relevance floor filters off-domain noise, not plausible-sounding questions
  the corpus cannot answer. "The proper way to baptize an infant in Islam"
  scores 0.4677, above the 0.35 floor. The refusal detector catches that one;
  "the best Islamic stock portfolio strategy" (0.3990) is caught by neither.
- The refusal detector is regex-based and errs towards refusing. It will
  sometimes decline a legitimate study question phrased like a ruling request.
- Answers come from one 1930s English translation and no tafsir. It is a
  finding aid, not a source of interpretation.
- Latency after warm-up was 2.4-4.1s in the two measurements taken before the
  API quota ran out. Baseline variance was 6.5-17.4s, so that range is not well
  established.

### Platform and scope

- Web only. No Android or iOS build has been attempted.
- `lib/surah_list_page.dart` is ~1800 lines holding the surah list, reader and
  assistant. It should be split; the layered `data/domain/presentation`
  structure the brief calls for exists only as a `data/` folder.
- `drift` is a dependency but unused: the web runtime reads bundled JSON only.
- Voice dictation sends **the audio of your voice** to the browser's speech
  service, off your device. The app asks before opening the microphone. Details
  in `docs/SOURCES.md`.
- Corpus verification exists as a test, not as a build step, so it only runs
  when someone runs the tests.
- Rate limiting is not implemented. The Gemini free tier was exhausted by a
  single afternoon of development profiling.

## Documentation

- `docs/BRIEF.md` - the original build brief and staged plan
- `docs/DECISIONS.md` - every significant decision with the measurements behind
  it, including the ones that were rejected and why
- `docs/SOURCES.md` - sources, licences, and third parties receiving user data
- `docs/eval_review.md` - the retrieval output used to relabel the benchmark
