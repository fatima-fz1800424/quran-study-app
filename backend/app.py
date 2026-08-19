import os
from typing import Any

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException

try:
    from google import genai  # type: ignore
except ImportError:  # pragma: no cover
    genai = None

try:
    from backend.retrieval import retriever
except ImportError:  # pragma: no cover
    from retrieval import retriever

load_dotenv()

app = FastAPI(title='Quran Study App Backend')

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
def search(q: str, k: int = 5) -> list[dict]:
    return retriever.search(q, k=k)


@app.post('/ask')
def ask(payload: dict[str, str]) -> dict[str, Any]:
    question = (payload or {}).get('question', '').strip()
    if not question:
        raise HTTPException(status_code=400, detail='Question is required.')

    chunks = retriever.search(question, k=5)
    references = [chunk['reference'] for chunk in chunks]
    context = '\n\n'.join(
        f"[{chunk['reference']}] {chunk['translation_text']}" for chunk in chunks
    )

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
    prompt = (
        f'{SYSTEM_PROMPT}\n\n'
        f'Question: {question}\n\n'
        f'Verses:\n{context}'
    )

    try:
        response = client.models.generate_content(
            model='gemini-3.6-flash',
            contents=prompt,
        )
    except Exception as exc:  # pragma: no cover - external API behavior
        raise HTTPException(
            status_code=502,
            detail=f'Gemini API call failed: {exc}',
        ) from exc

    return {
        'status': 'ok',
        'question': question,
        'system_prompt': SYSTEM_PROMPT,
        'context': context,
        'references': references,
        'answer': response.text,
    }
