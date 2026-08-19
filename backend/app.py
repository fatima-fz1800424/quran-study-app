import logging
import os
import time
from typing import Any, NamedTuple

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

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
RETRIEVAL_MODEL = 'sentence-transformers/all-mpnet-base-v2'

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

app = FastAPI(title='Quran Study App Backend')


@app.on_event('startup')
async def startup_event() -> None:
    startup_start = time.perf_counter()
    logger.info('FastAPI startup: warming Quran retriever...')
    # warm the retriever with the chosen production model (mpnet)
    retriever.initialize(model_name='sentence-transformers/all-mpnet-base-v2')
    logger.info('FastAPI startup: complete in %.2fs', time.perf_counter() - startup_start)

# Development-only CORS: allow Flutter web clients served from localhost on any port.
# This must be tightened to specific origins before deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=['http://localhost', 'http://127.0.0.1'],
    allow_origin_regex=r'https?://localhost(:\d+)?$|https?://127\.0\.0\.1(:\d+)?$',
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
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
- Answer in two or three sentences, then name the surah:verse references you used. Do not pad, do not restate the question, do not add a preamble.
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
def health() -> dict[str, str]:
    _ = os.getenv('GEMINI_API_KEY')
    return {'status': 'ok'}


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
    api_key = os.getenv('GEMINI_API_KEY')
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail='GEMINI_API_KEY is not set in the environment for this process.',
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
