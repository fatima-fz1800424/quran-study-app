"""Embed the verse corpus with Google's embedding API, a day at a time.

Google's free tier allows 1000 embed_content units per day per model, and the
quota counts individual texts rather than HTTP calls - measured: at the same
moment, a batch of 1 succeeded while batches of 5 and 50 were both refused with
the same quota metric. The corpus is 6236 verses, so on the free tier this is a
seven-day job. This script makes that survivable: run it once a day, it takes
whatever quota is available, checkpoints, and exits 0 rather than crashing.

    # do today's share
    python backend/tools/embed_corpus_gemini.py

    # check progress without spending any quota
    python backend/tools/embed_corpus_gemini.py --status

Needs GEMINI_API_KEY in the environment. State lives in
backend/.retrieval_cache/, which is gitignored, so neither the 19MB matrix nor
anything else here can be committed by accident.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent.parent
CORPUS = ROOT / 'backend' / 'corpus.json'
CACHE = ROOT / 'backend' / '.retrieval_cache'

MODEL = 'gemini-embedding-001'
DIM = 768

# 001 rather than the newer gemini-embedding-2: task_type is honoured on 001
# and silently ignored on -2 (measured cos(RETRIEVAL_DOCUMENT, RETRIEVAL_QUERY)
# of 0.876 versus 1.000000). Question-against-verse is asymmetric retrieval, so
# that distinction is the largest quality lever available at no cost.
DOC_TASK = 'RETRIEVAL_DOCUMENT'

# The API rejects more than 100 per call outright, and 100 drew a 429 on the
# free tier. Start at 50 and walk down when the quota tightens.
BATCH_LADDER = (50, 20, 5, 1)

STATE = CACHE / f'gemini_embed_{DIM}.state.json'
PARTIAL = CACHE / f'gemini_embed_{DIM}.partial.npy'
FINAL = CACHE / f'embeddings_{MODEL}.npy'
FINAL_META = CACHE / f'metadata_{MODEL}.json'


def load_corpus() -> tuple[list[str], list[str]]:
    chunks = json.loads(CORPUS.read_text(encoding='utf-8'))
    return (
        [c['embedding_text'] for c in chunks],
        [c['reference'] for c in chunks],
    )


def corpus_signature(texts: list[str]) -> str:
    """The same signature retrieval.py computes, so the output is drop-in.

    Mirrors QuranRetriever._load_or_build_embeddings. Reimplemented rather than
    imported because importing retrieval.py pulls in torch, and the entire
    point of this exercise is a runtime with no torch in it.
    """
    return hashlib.sha256(
        ('\n'.join(texts) + f'\nmodel={MODEL}').encode('utf-8')
    ).hexdigest()


def read_state(total: int) -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text(encoding='utf-8'))
    return {'done': 0, 'total': total, 'days': [], 'model': MODEL, 'dim': DIM}


def write_state(state: dict) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=1), encoding='utf-8')


def show_status(state: dict, total: int) -> None:
    done = state['done']
    pct = 100.0 * done / total if total else 0.0
    print(f'corpus      : {total} verses')
    print(f'embedded    : {done} ({pct:.1f}%)')
    print(f'remaining   : {total - done}')
    if state.get('days'):
        print('history     :')
        for entry in state['days'][-10:]:
            print(f"  {entry['date']}  +{entry['added']:4} verses "
                  f"in {entry['seconds']:6.1f}s  ({entry['reason']})")
        recent = [d['added'] for d in state['days'][-3:] if d['added'] > 0]
        if recent and done < total:
            per_day = sum(recent) / len(recent)
            print(f'\nat ~{per_day:.0f}/day, about '
                  f'{(total - done) / per_day:.1f} more run(s) to finish')
    if done >= total:
        print(f'\nCOMPLETE. Matrix at {FINAL.name}'
              f' ({FINAL.stat().st_size:,} bytes)' if FINAL.exists() else '')
    else:
        print('\nrun without --status to take today\'s share')


def finalise(vectors: np.ndarray, refs: list[str], signature: str) -> None:
    """Normalise and write the matrix in the layout retrieval.py expects."""
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    vectors = (vectors / np.where(norms == 0, 1.0, norms)).astype(np.float32)
    np.save(FINAL, vectors)
    FINAL_META.write_text(
        json.dumps(
            {
                'signature': signature,
                'references': refs,
                'model_name': MODEL,
                'dim': DIM,
                'task_type': DOC_TASK,
                'source': 'google generativelanguage embed_content, free tier',
            },
            ensure_ascii=False,
        ),
        encoding='utf-8',
    )
    print(f'\nCOMPLETE: {FINAL} ({FINAL.stat().st_size:,} bytes)')
    print(f'          {FINAL_META.name} written alongside it')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--status', action='store_true',
                        help='report progress without calling the API')
    parser.add_argument('--limit', type=int, default=1000,
                        help='stop after this many verses today (default 1000, '
                             'the free-tier daily allowance)')
    parser.add_argument('--max-minutes', type=float, default=20.0,
                        help='wall-clock ceiling for one run (default 20). A '
                             'daily job must never spin for hours.')
    args = parser.parse_args()

    texts, refs = load_corpus()
    total = len(texts)
    state = read_state(total)

    if args.status:
        show_status(state, total)
        return 0

    key = os.getenv('GEMINI_API_KEY', '').strip()
    if not key:
        print('GEMINI_API_KEY is not set in this environment.', file=sys.stderr)
        return 2

    from google import genai
    from google.genai import types

    client = genai.Client(api_key=key)
    signature = corpus_signature(texts)

    vectors = np.zeros((total, DIM), dtype=np.float32)
    done = state['done']
    if done and PARTIAL.exists():
        saved = np.load(PARTIAL)
        vectors[:done] = saved[:done]
        print(f'resuming from {done}/{total}')
    elif done:
        print(f'state says {done} done but {PARTIAL.name} is missing; restarting')
        done = 0

    started = time.perf_counter()
    start_done = done
    reason = 'target reached'
    ladder = 0
    # Consecutive quota waits that produced no verses. Two is enough to
    # conclude the daily allowance is gone: the server hands out a ~57s retry
    # hint for the daily cap just as it does for the per-minute window, so the
    # delay it asks for says nothing about which limit was hit. Only whether a
    # single-verse request succeeds afterwards does.
    stalls = 0
    deadline = started + args.max_minutes * 60

    while done < total and (done - start_done) < args.limit:
        if time.perf_counter() > deadline:
            reason = f'hit the {args.max_minutes:g}-minute wall-clock ceiling'
            break
        size = min(BATCH_LADDER[ladder], total - done,
                   args.limit - (done - start_done))
        batch = texts[done:done + size]
        try:
            resp = client.models.embed_content(
                model=MODEL,
                # A list of Content objects, one per verse. Passing list[str]
                # or list[Part] instead returns a SINGLE vector for the whole
                # batch, with no error - it treats them as one concatenated
                # document. That silently produces a useless corpus.
                contents=[types.Content(parts=[types.Part(text=t)]) for t in batch],
                config=types.EmbedContentConfig(
                    task_type=DOC_TASK, output_dimensionality=DIM
                ),
            )
            got = [e.values for e in resp.embeddings]
            if len(got) != len(batch):
                raise RuntimeError(
                    f'asked for {len(batch)} vectors, got {len(got)}'
                )
            vectors[done:done + len(got)] = np.asarray(got, dtype=np.float32)
            done += len(got)
            # Progress resets the stall count, and only a success earns a step
            # back up the ladder - climbing after a mere wait is what made an
            # earlier version re-walk 50 -> 20 -> 5 -> 1 forever, spending
            # three rejected requests per cycle and never finishing.
            stalls = 0
            if ladder > 0:
                ladder -= 1

            if done % 500 < size or done == total:
                np.save(PARTIAL, vectors)
                state['done'] = done
                write_state(state)
                print(f'  {done:5}/{total}  '
                      f'{time.perf_counter() - started:6.1f}s elapsed')

        except Exception as exc:  # noqa: BLE001
            msg = str(exc)
            if '429' not in msg:
                np.save(PARTIAL, vectors)
                state['done'] = done
                write_state(state)
                print(f'\nstopped on a non-quota error: {msg[:300]}',
                      file=sys.stderr)
                return 1

            if ladder + 1 < len(BATCH_LADDER):
                ladder += 1
                print(f'  429 at batch {size}; dropping to '
                      f'{BATCH_LADDER[ladder]}')
                continue

            # Even a single verse is refused. That is either the per-minute
            # window or the daily cap, and the error does not distinguish them,
            # so wait the requested time and find out empirically.
            reason = 'daily quota exhausted'
            if stalls >= 2:
                break
            hint = re.search(r'retry in ([0-9.]+)s', msg)
            wait = min(float(hint.group(1)) if hint else 60.0, 90.0)
            if time.perf_counter() + wait > deadline:
                reason = f'hit the {args.max_minutes:g}-minute wall-clock ceiling'
                break
            stalls += 1
            print(f'  429 at batch 1; waiting {wait:.0f}s '
                  f'(attempt {stalls} of 2)')
            time.sleep(wait + 1)
            # Stay at batch 1. Anything larger is certain to be refused while
            # the allowance is this tight.
            continue

    elapsed = time.perf_counter() - started
    added = done - start_done
    np.save(PARTIAL, vectors)
    state['done'] = done
    state.setdefault('days', []).append({
        'date': time.strftime('%Y-%m-%d %H:%M'),
        'added': added,
        'seconds': round(elapsed, 1),
        'reason': reason,
    })
    write_state(state)

    print(f'\nadded {added} verses in {elapsed:.1f}s ({reason})')
    print(f'progress: {done}/{total} ({100.0 * done / total:.1f}%)')

    if done >= total:
        finalise(vectors, refs, signature)
    else:
        remaining = total - done
        print(f'{remaining} to go. Run this again tomorrow; '
              f'--status reports progress without spending quota.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
