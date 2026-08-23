import logging
import os
import time
from collections import OrderedDict, deque
from typing import Any, NamedTuple

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

try:
    from google import genai  # type: ignore
    from google.genai import types as genai_types  # type: ignore
except ImportError:  # pragma: no cover
    genai = None
    genai_types = None

try:
    from backend.retrieval import retriever
except ImportError:  # pragma: no cover
    from retrieval import retriever

try:
    from backend.guardrails import (
        NO_SOURCE_MESSAGE,
        RULING_REDIRECT_MESSAGE,
        is_ruling_question,
        relevant_chunks,
        verified_citations,
    )
except ImportError:  # pragma: no cover
    from guardrails import (
        NO_SOURCE_MESSAGE,
        RULING_REDIRECT_MESSAGE,
        is_ruling_question,
        relevant_chunks,
        verified_citations,
    )

GEMINI_MODEL = 'gemini-3.6-flash'
# Overridable so that the small-model image variant (`--build-arg RETRIEVAL_MODEL=...`)
# serves the same model whose embeddings were baked into it. Validated against
# ALLOWED_RETRIEVAL_MODELS at startup rather than trusted blindly.
RETRIEVAL_MODEL = (
    os.getenv('RETRIEVAL_MODEL', '').strip() or 'sentence-transformers/all-mpnet-base-v2'
)

# A grounded two-or-three sentence answer plus references does not need more
# than this, and generation is output-token-bound: measured answers of 532 and
# 1195 characters took 7.4s and 17.4s respectively.
#
# Careful: this budget is shared with thinking tokens on this model. With
# thinking left at its default, 300 was consumed almost entirely by thinking
# (~285 tokens), leaving 9-12 for the answer, which truncated every reply into
# an uncited fragment. It is only safe alongside the thinking setting below.
MAX_OUTPUT_TOKENS = 300

# This model thinks by default, and measurement showed it spending far more on
# thinking than on answering: 706-858 thinking tokens against 121-271 output
# tokens. Reading verses out of a supplied context and summarising them in two
# sentences does not need that, and it was the single largest cost in the call.
THINKING_LEVEL = 'MINIMAL'

# Loading a model means downloading weights and embedding 6236 verses, which
# takes minutes. An arbitrary model name from a request must not be able to
# trigger that, so /search accepts only models we have already benchmarked.
ALLOWED_RETRIEVAL_MODELS = {
    'sentence-transformers/all-mpnet-base-v2',
    'sentence-transformers/all-MiniLM-L6-v2',
}


class GeminiReply(NamedTuple):
    """A model reply plus what it cost, so latency can be attributed."""

    text: str
    usage: dict[str, Any]


class AskPlan(NamedTuple):
    """Everything decided about a question before the model is involved.

    Shared by /ask and /ask/plan so the two cannot disagree about whether a
    question is refused or which verses ground it.
    """

    status: str  # 'ok', 'refused_ruling' or 'no_source'
    chunks: list[dict]
    message: str  # the reply for a terminal status, empty when status is 'ok'
    timings: dict[str, float]

load_dotenv()

logger = logging.getLogger('quran_backend')
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')

GEMINI_KEY_ENV = 'GEMINI_API_KEY'


def _gemini_key() -> str:
    """The configured Gemini key, or an empty string.

    Read through one function so that "is it configured" and "use it" cannot
    drift apart, and so that nothing else in the module touches the variable
    directly and risks logging it.
    """
    return os.getenv(GEMINI_KEY_ENV, '').strip()


def _int_env(name: str, default: int) -> int:
    """An integer setting from the environment, falling back loudly."""
    raw = os.getenv(name, '').strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        logger.warning('%s=%r is not an integer; falling back to %d', name, raw, default)
        return default


# Rate limits. The per-IP window is the cheap first line; the daily ceiling is
# the one that actually protects the bill, because a per-IP limit does nothing
# against a caller who has more than one address.
ASK_RATE_LIMIT = _int_env('ASK_RATE_LIMIT', 10)
ASK_RATE_WINDOW_S = _int_env('ASK_RATE_WINDOW_S', 60)
READ_RATE_LIMIT = _int_env('READ_RATE_LIMIT', 60)
READ_RATE_WINDOW_S = _int_env('READ_RATE_WINDOW_S', 60)
ASK_DAILY_BUDGET = _int_env('ASK_DAILY_BUDGET', 500)

# Only meaningful behind a proxy that overwrites the header, which is what
# Railway, Render and Fly all do. Off by default: trusting X-Forwarded-For on a
# directly reachable service lets any caller mint a fresh identity per request
# and walk straight through the per-IP limit.
TRUST_PROXY_HEADERS = os.getenv('TRUST_PROXY_HEADERS', '').strip() == '1'

# Paths that spend money, as opposed to paths that only spend CPU.
_BILLED_PATHS = {'/ask'}

# Paths that must never be throttled: platform health checks poll them.
_UNLIMITED_PATHS = {'/health'}

app = FastAPI(title='Quran Study App Backend')


@app.on_event('startup')
async def startup_event() -> None:
    startup_start = time.perf_counter()

    # Checked first, before the multi-second model load, and fatal by default.
    # A missing key used to surface as a 500 for whichever visitor happened to
    # ask the first question, by which point the service had been reporting
    # itself healthy for however long it had been up. A misconfigured
    # deployment should refuse to start, and say why.
    if not _gemini_key():
        if os.getenv('ALLOW_MISSING_GEMINI_KEY', '').strip() == '1':
            logger.warning(
                'Starting without %s because ALLOW_MISSING_GEMINI_KEY=1. '
                '/search and /related will work; /ask will return HTTP 500.',
                GEMINI_KEY_ENV,
            )
        else:
            raise RuntimeError(
                f'{GEMINI_KEY_ENV} is not set, so /ask cannot work. Set it in the '
                f'environment of this process, or in a .env file for local runs. '
                f'To start anyway for retrieval-only work, set '
                f'ALLOW_MISSING_GEMINI_KEY=1.'
            )

    if RETRIEVAL_MODEL not in ALLOWED_RETRIEVAL_MODELS:
        raise RuntimeError(
            f'RETRIEVAL_MODEL={RETRIEVAL_MODEL!r} is not one of the benchmarked '
            f'models {sorted(ALLOWED_RETRIEVAL_MODELS)}. Loading an unknown model '
            f'means downloading weights and re-embedding the corpus at boot.'
        )

    logger.info('FastAPI startup: warming Quran retriever...')
    # warm the retriever with the chosen production model (mpnet)
    retriever.initialize(model_name=RETRIEVAL_MODEL)
    logger.info('FastAPI startup: complete in %.2fs', time.perf_counter() - startup_start)


class _FixedWindowCounter:
    """Per-key request counts over a sliding window.

    In-process, and therefore per-replica: two instances behind a load balancer
    would each allow the full limit, and a restart forgets everything. That is
    accepted deliberately for a single-instance free-tier deployment, because
    the alternative is a Redis dependency - a second service to host and pay
    for. Move to slowapi with a Redis backend once there is more than one
    replica.
    """

    def __init__(self, max_keys: int = 4096) -> None:
        self._hits: OrderedDict[tuple[str, str], deque[float]] = OrderedDict()
        self._max_keys = max_keys

    def retry_after(
        self, key: tuple[str, str], limit: int, window: float, now: float
    ) -> int:
        """0 if the request is allowed, else the seconds to wait before retrying."""
        hits = self._hits.get(key)
        if hits is None:
            # Bounded, so that a flood of distinct source addresses cannot turn
            # the limiter itself into the memory leak that takes the box down.
            while len(self._hits) >= self._max_keys:
                self._hits.popitem(last=False)
            hits = deque()
            self._hits[key] = hits
        self._hits.move_to_end(key)

        cutoff = now - window
        while hits and hits[0] <= cutoff:
            hits.popleft()

        if len(hits) >= limit:
            return max(1, int(window - (now - hits[0])) + 1)

        hits.append(now)
        return 0


_rate_counter = _FixedWindowCounter()

# [UTC day number, billed calls so far] for the whole-service daily ceiling.
_ask_budget_day: list[Any] = [None, 0]


def _seconds_until_utc_midnight(now_wall: float) -> int:
    return max(1, 86400 - int(now_wall) % 86400)


def _daily_budget_exhausted(now_wall: float) -> bool:
    """Count one billed call against today's ceiling, or refuse it."""
    if ASK_DAILY_BUDGET <= 0:
        return False
    today = int(now_wall) // 86400
    if _ask_budget_day[0] != today:
        _ask_budget_day[0] = today
        _ask_budget_day[1] = 0
    if _ask_budget_day[1] >= ASK_DAILY_BUDGET:
        return True
    _ask_budget_day[1] += 1
    return False


def _client_ip(request: Request) -> str:
    if TRUST_PROXY_HEADERS:
        forwarded = request.headers.get('x-forwarded-for', '')
        if forwarded:
            # Leftmost entry is the original client; each proxy appends itself.
            return forwarded.split(',')[0].strip() or 'unknown'
    return request.client.host if request.client else 'unknown'


# Registered before CORS on purpose. Starlette treats the most recently added
# middleware as the outermost, so adding CORS afterwards means a 429 leaving
# here still passes back out through CORS. Without that ordering the browser
# reports the rejection as an opaque CORS failure and the real status never
# reaches the Flutter client's error handling.
@app.middleware('http')
async def rate_limit(request: Request, call_next):
    path = request.url.path
    if request.method == 'OPTIONS' or path in _UNLIMITED_PATHS:
        return await call_next(request)

    billed = path in _BILLED_PATHS
    limit, window = (
        (ASK_RATE_LIMIT, ASK_RATE_WINDOW_S) if billed
        else (READ_RATE_LIMIT, READ_RATE_WINDOW_S)
    )
    client = _client_ip(request)

    retry_after = _rate_counter.retry_after(
        (client, 'billed' if billed else 'read'),
        limit,
        float(window),
        time.monotonic(),
    )
    if retry_after:
        logger.warning('rate limit: %s %s from %s', request.method, path, client)
        return JSONResponse(
            status_code=429,
            content={
                'detail': (
                    f'Too many requests. This endpoint allows {limit} per '
                    f'{window}s. Retry in {retry_after}s.'
                )
            },
            headers={'Retry-After': str(retry_after)},
        )

    if billed:
        now_wall = time.time()
        if _daily_budget_exhausted(now_wall):
            wait = _seconds_until_utc_midnight(now_wall)
            logger.error(
                'daily /ask budget of %d exhausted; refusing until UTC midnight',
                ASK_DAILY_BUDGET,
            )
            return JSONResponse(
                status_code=429,
                content={
                    'detail': (
                        'The assistant has reached its daily question limit for '
                        'this deployment. Reading, search and recitation are '
                        'unaffected. Please try again tomorrow.'
                    )
                },
                headers={'Retry-After': str(wait)},
            )

    return await call_next(request)


# CORS. With ALLOWED_ORIGINS set (comma-separated), exactly those origins are
# permitted; that is the deployed configuration, where the Flutter web build is
# served from a different domain than this API. With it unset only localhost is
# allowed, which is the development default.
#
# allow_credentials is off: this API uses no cookies and no browser-managed
# auth, so advertising credential support would only widen what a hostile page
# could do with a visitor's browser.
_configured_origins = [
    origin.strip()
    for origin in os.getenv('ALLOWED_ORIGINS', '').split(',')
    if origin.strip()
]
if _configured_origins:
    _cors_origin_kwargs: dict[str, Any] = {'allow_origins': _configured_origins}
    logger.info('CORS: allowing configured origins: %s', ', '.join(_configured_origins))
else:
    _cors_origin_kwargs = {
        'allow_origins': ['http://localhost', 'http://127.0.0.1'],
        'allow_origin_regex': r'https?://localhost(:\d+)?$|https?://127\.0\.0\.1(:\d+)?$',
    }
    logger.warning(
        'CORS: ALLOWED_ORIGINS is unset, so only localhost origins are permitted. '
        'Set it to the deployed frontend origin before going public.'
    )

app.add_middleware(
    CORSMiddleware,
    allow_credentials=False,
    allow_methods=['GET', 'POST', 'OPTIONS'],
    allow_headers=['Content-Type'],
    **_cors_origin_kwargs,
)

SYSTEM_PROMPT = """You are a Quran study aid that answers only from the verses provided in the user prompt.

Decision procedure before answering:
- Before answering, decide: does at least one provided verse directly address the question's subject? Not merely share a theme, not relate loosely — directly address it.
- If no, respond only with the insufficiency message. Do not answer partially. Do not offer a general reflection instead.
- Do not answer from a weakly related verse just because it feels adjacent.

Rules:
- Answer ONLY from the provided verses. Never use your own knowledge of the Quran or make up details.
- Every answer must cite the surah:verse references used.
- If the provided verses do not address the question, say so plainly and do not answer. Do not stretch a loosely related verse into an answer.
- Do not paraphrase or interpret a verse to make it fit the question. Do not combine unrelated verses to construct an answer neither one supports.
- Never issue religious rulings. Do not give halal/haram judgments, do not judge worship validity, and do not advise on personal, family, or marital matters. If the question is about those topics, redirect the user to a qualified scholar or local imam.
- If the user rephrases a ruling question as a general or hypothetical one, it is still a ruling question. Redirect regardless of framing.
- Never generate Arabic text. Cite verse references only; the app renders Arabic from its verified local database.
- State that this is a study aid based on the Yusuf Ali translation, not a scholarly source.
- Answer in two or three sentences. Do not pad, do not restate the question, do not add a preamble.
- Cite each reference inline, in the sentence that uses it, like: 'Patience is joined to prayer in 2:45.'
- Do not end with a separate 'References', 'Sources' or 'Citations' line, and do not list the references again after the answer. The app displays them itself, so a trailing list appears twice to the reader.
- Keep the answer concise, clear, and grounded in the supplied verses only.
- Use the exact verses provided in the prompt as your source. Do not infer unsupported conclusions.
- If the verses are insufficient, say: 'The verses I have do not answer this question.'

Calibration note:
- The verses you receive are selected by an imperfect automated search. They are frequently NOT the most relevant verses in the Quran on this topic. A relevant-sounding verse may be a poor match.
- When in doubt, say the verses do not answer the question. Declining is always acceptable and is never a failure.

Grounding requirement:
- Only answer when the supplied verses directly support the point.
- If they do not, explicitly say that the available verses do not answer the question and stop.
"""


@app.get('/health')
def health() -> dict[str, Any]:
    """Liveness, plus enough configuration detail to diagnose a bad deploy.

    Returns 200 whenever the process is serving. It reports *whether* a Gemini
    key is configured and never any part of its value; startup refuses to come
    up without one, so a reachable /health already implies a key is present
    unless ALLOW_MISSING_GEMINI_KEY was set.

    The previous version read the key into a discarded variable, which looked
    like a check but asserted nothing.
    """
    return {
        'status': 'ok',
        'retrieval_model': getattr(retriever, '_loaded_model_name', None) or retriever.model_name,
        'corpus_chunks': len(retriever.chunks),
        'gemini_key_configured': bool(_gemini_key()),
    }


@app.get('/search')
def search(
    q: str,
    k: int = 5,
    strategy: str = 'dense',
    threshold: float | None = None,
    model_name: str | None = None,
) -> list[dict]:
    if model_name is not None and model_name not in ALLOWED_RETRIEVAL_MODELS:
        raise HTTPException(
            status_code=400,
            detail=(
                f'Unsupported model_name {model_name!r}. Loading a model means '
                f'downloading weights and embedding the whole corpus, so only '
                f'pre-benchmarked models are accepted: '
                f'{sorted(ALLOWED_RETRIEVAL_MODELS)}'
            ),
        )
    return retriever.search(q, k=k, strategy=strategy, threshold=threshold, model_name=model_name)


def _call_gemini(prompt: str) -> GeminiReply:
    """Send `prompt` to Gemini and return the reply text plus token usage.

    Kept as a single seam so tests can replace the model call without needing an
    API key or network access.
    """
    # Startup already refuses to boot without a key, so this is defence in
    # depth for the ALLOW_MISSING_GEMINI_KEY case rather than the primary check.
    api_key = _gemini_key()
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail=f'{GEMINI_KEY_ENV} is not set in the environment for this process.',
        )

    if genai is None:
        raise HTTPException(
            status_code=500,
            detail='google-genai is not installed. Install the google-genai SDK before calling Gemini.',
        )

    client = genai.Client(api_key=api_key)
    try:
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=genai_types.GenerateContentConfig(
                max_output_tokens=MAX_OUTPUT_TOKENS,
                thinking_config=genai_types.ThinkingConfig(
                    thinking_level=THINKING_LEVEL,
                ),
            ),
        )
    except Exception as exc:  # pragma: no cover - external API behavior
        # The client shows `detail` to the user, so it must be readable and must
        # not carry provider internals. The full error goes to the log instead.
        logger.exception('Gemini call failed')
        text = str(exc)
        if '429' in text or 'RESOURCE_EXHAUSTED' in text:
            raise HTTPException(
                status_code=503,
                detail=(
                    'The study assistant has reached its request limit for now. '
                    'Reading, search and bookmarks still work. Please try asking '
                    'again later.'
                ),
            ) from exc
        raise HTTPException(
            status_code=502,
            detail=(
                'The study assistant could not be reached. Please try again in '
                'a moment.'
            ),
        ) from exc

    metadata = getattr(response, 'usage_metadata', None)
    usage = {
        'prompt_tokens': getattr(metadata, 'prompt_token_count', None),
        'output_tokens': getattr(metadata, 'candidates_token_count', None),
        # Non-zero means the model spent time on internal reasoning we are
        # paying for in latency.
        'thinking_tokens': getattr(metadata, 'thoughts_token_count', None),
        'total_tokens': getattr(metadata, 'total_token_count', None),
    }
    return GeminiReply(text=response.text or '', usage=usage)


def _plan_answer(question: str) -> AskPlan:
    """Decide, without calling the model, whether and how to answer.

    Reports its own sub-stage timings so both callers keep the guardrail and
    retrieval legs separated rather than lumped together.
    """
    timings: dict[str, float] = {}

    start = time.perf_counter()
    ruling = is_ruling_question(question)
    timings['guardrail_ms'] = round((time.perf_counter() - start) * 1000, 1)
    if ruling:
        return AskPlan('refused_ruling', [], RULING_REDIRECT_MESSAGE, timings)

    # Use the winning retrieval variant: dense mpnet embeddings by default
    start = time.perf_counter()
    chunks = relevant_chunks(
        retriever.search(question, k=5, model_name=RETRIEVAL_MODEL)
    )
    timings['retrieval_ms'] = round((time.perf_counter() - start) * 1000, 1)

    if not chunks:
        return AskPlan('no_source', [], NO_SOURCE_MESSAGE, timings)
    return AskPlan('ok', chunks, '', timings)


@app.post('/ask/plan')
def ask_plan(payload: dict[str, str]) -> dict[str, Any]:
    """The fast half of /ask: refusal decision and retrieval, no model call.

    Exists so the client can show real progress instead of an unbroken spinner.
    A refusal comes back in single-digit milliseconds and the verses in tens, so
    the user learns their question was refused, or sees which verses were found,
    long before the answer is composed. Deliberately not a streaming endpoint:
    the Flutter web client buffers streamed responses whole, so a second short
    request achieves what SSE could not, without a new dependency.

    /ask does not trust this and repeats the work, so a client that skips this
    endpoint gets identical behaviour.
    """
    started = time.perf_counter()
    question = (payload or {}).get('question', '').strip()
    if not question:
        raise HTTPException(status_code=400, detail='Question is required.')

    plan = _plan_answer(question)
    elapsed = round((time.perf_counter() - started) * 1000, 1)
    logger.info(
        '/ask/plan status=%s total=%.0fms %s',
        plan.status,
        elapsed,
        ' '.join(f'{k}={v}ms' for k, v in plan.timings.items()),
    )

    return {
        'status': plan.status,
        'question': question,
        'references': [chunk['reference'] for chunk in plan.chunks],
        'verses': [
            {
                'reference': chunk['reference'],
                'translation_text': chunk['translation_text'],
            }
            for chunk in plan.chunks
        ],
        'answer': plan.message,
        'timings': {**plan.timings, 'total_ms': elapsed},
    }


@app.post('/ask')
def ask(payload: dict[str, str]) -> dict[str, Any]:
    started = time.perf_counter()
    timings: dict[str, float] = {}

    def mark(stage: str, since: float) -> float:
        now = time.perf_counter()
        timings[stage] = round((now - since) * 1000, 1)
        return now

    question = (payload or {}).get('question', '').strip()
    if not question:
        raise HTTPException(status_code=400, detail='Question is required.')

    def finish(result: dict[str, Any]) -> dict[str, Any]:
        timings['total_ms'] = round((time.perf_counter() - started) * 1000, 1)
        logger.info(
            '/ask status=%s total=%.0fms %s',
            result['status'],
            timings['total_ms'],
            ' '.join(f'{k}={v}ms' for k, v in timings.items() if k != 'total_ms'),
        )
        return {**result, 'timings': timings}

    # Ruling questions never reach the model, and retrieval below has a
    # relevance floor: retrieval always returns its k best however weak, and
    # without a floor an off-topic question arrives dressed as sourced context.
    # Both decisions live in _plan_answer so /ask/plan cannot disagree.
    plan = _plan_answer(question)
    timings.update(plan.timings)
    stage_start = time.perf_counter()
    if plan.status != 'ok':
        return finish({
            'status': plan.status,
            'question': question,
            'system_prompt': SYSTEM_PROMPT,
            'context': '',
            'references': [],
            'citations': [],
            'answer': plan.message,
            'usage': {},
        })

    chunks = plan.chunks
    references = [chunk['reference'] for chunk in chunks]
    context = '\n\n'.join(
        f"[{chunk['reference']}] {chunk['translation_text']}" for chunk in chunks
    )

    prompt = (
        f'{SYSTEM_PROMPT}\n\n'
        f'Question: {question}\n\n'
        f'Verses:\n{context}'
    )
    stage_start = mark('prompt_build_ms', stage_start)

    reply = _call_gemini(prompt)
    stage_start = mark('gemini_ms', stage_start)

    # An answer we cannot trace back to a retrieved verse is not a sourced
    # answer, whatever it sounds like. Citations of verses that were never
    # retrieved are discarded, and an answer left with none is not shown.
    citations = verified_citations(reply.text, references)
    mark('citation_check_ms', stage_start)
    if not citations:
        return finish({
            'status': 'no_source',
            'question': question,
            'system_prompt': SYSTEM_PROMPT,
            'context': context,
            'references': references,
            'citations': [],
            'answer': NO_SOURCE_MESSAGE,
            'usage': reply.usage,
        })

    return finish({
        'status': 'ok',
        'question': question,
        'system_prompt': SYSTEM_PROMPT,
        'context': context,
        'references': references,
        'citations': citations,
        'answer': reply.text,
        'usage': reply.usage,
    })


@app.get('/related')
def related(
    surah: int,
    verse: int,
    k: int = 5,
    rerank: bool = False,
    min_score: float = 0.70,
    max_same_surah: int = 2,
    cross_surah_gate_score: float = 0.65,
) -> dict[str, Any]:
    """Related verses endpoint.

    Defaults:
    - `min_score=0.70` - how strong a match must be to be shown
    - `cross_surah_gate_score=0.65` - how much cross-surah resonance the verse
      must have before any results are returned at all
    - `max_same_surah=2` - caps results from the target's own surah only
    - `rerank=False` (optional)

    Returns fewer than `k` results when the threshold filters them; returns an empty list if nothing qualifies.
    """
    try:
        results = retriever.get_related(
            surah,
            verse,
            k=k,
            model_name='sentence-transformers/all-mpnet-base-v2',
            max_same_surah=max_same_surah,
            min_score=min_score,
            rerank=rerank,
            cross_surah_gate_score=cross_surah_gate_score,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    return {
        'status': 'ok',
        'query': f'{surah}:{verse}',
        'results': results,
    }
