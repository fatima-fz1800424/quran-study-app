# Quran Study App Backend

FastAPI backend for the Quran Study App. It holds the LLM API key, runs
retrieval over the bundled translation corpus, and serves the study assistant.
The mobile and web clients never call the LLM directly.

## Install

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## Environment

The app reads the Gemini API key from the `GEMINI_API_KEY` environment
variable. `/ask` returns HTTP 500 without it; every other endpoint works
without a key.

```bash
export GEMINI_API_KEY="your_key_here"
# Windows PowerShell:
# $env:GEMINI_API_KEY = "your_key_here"
```

A `.env` file in the project root is also read, via `python-dotenv`. It is
gitignored - do not commit a key.

## Run

Port 8123 is not arbitrary: it is what the Flutter client has hardcoded in
`kQuranBackendBaseUrl` (`lib/surah_list_page.dart`). Change one and you must
change the other.

```bash
uvicorn app:app --reload --host 127.0.0.1 --port 8123
```

First start is slow. The retriever loads `all-mpnet-base-v2` and, if
`backend/.retrieval_cache/` has no embeddings for that model, embeds the whole
6236-verse corpus before serving. That cache is gitignored, so a fresh clone
pays this cost once. Later starts read the cached vectors and take a few
seconds.

## Endpoints

### Health

```bash
curl http://127.0.0.1:8123/health
```

```json
{"status": "ok"}
```

### Search

Raw retrieval, no LLM. Useful for checking what the assistant would be given.

```bash
curl "http://127.0.0.1:8123/search?q=patience%20in%20hardship&k=5"
```

Optional: `strategy` (`dense`, `hybrid`, `rerank`), `threshold`, `model_name`.

### Ask

The study assistant. Retrieves verses, then answers only from them.

```bash
curl -X POST http://127.0.0.1:8123/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "what does the Quran say about patience"}'
```

Guardrails run in this process, before and after the model call:

- Ruling questions are refused without calling the model at all, and the reply
  points to a qualified scholar. This covers rephrasings such as "what does
  Islam say about ..." as well as direct halal/haram questions.
- If retrieval finds nothing above the relevance floor, the endpoint says it has
  no source instead of calling the model.
- An answer that cites nothing, or cites only verses that were not retrieved, is
  replaced with the no-source reply. A substantive answer always names verses
  that were actually in its context.

The response carries `status` (`ok`, `refused_ruling`, or `no_source`), the
`references` retrieved, and `citations` verified against them.

### Related

Verses related to a given verse. See `docs/DECISIONS.md` for how the
cross-surah gate and the display threshold differ.

```bash
curl "http://127.0.0.1:8123/related?surah=2&verse=255"
```

Optional: `k`, `min_score`, `cross_surah_gate_score`, `max_same_surah`,
`rerank`. Returns an empty `results` list when nothing qualifies.

## Tests

```bash
cd backend
python -m pytest
```

The guardrail tests mock the Gemini call, so they need no API key and no
network. They cover refusal behaviour and prompt construction, not model output.
