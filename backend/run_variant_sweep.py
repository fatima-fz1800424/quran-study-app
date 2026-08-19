import json
import math
import time
from pathlib import Path
from typing import List, Tuple

import numpy as np
from sentence_transformers import SentenceTransformer, CrossEncoder
from rank_bm25 import BM25Okapi

ROOT = Path(__file__).resolve().parent
CORPUS_PATH = ROOT / 'corpus.json'
EVAL_PATH = ROOT / 'eval_queries.json'
CACHE_DIR = ROOT / '.retrieval_cache'
CACHE_DIR.mkdir(parents=True, exist_ok=True)


def load_corpus():
    with CORPUS_PATH.open('r', encoding='utf-8') as f:
        return json.load(f)


def texts_for_embedding(chunks):
    return [c['embedding_text'] for c in chunks]


def load_or_build_embeddings(model_name: str, chunks) -> np.ndarray:
    key = model_name.replace('/', '_')
    emb_path = CACHE_DIR / f'embeddings_{key}.npy'
    meta_path = CACHE_DIR / f'meta_{key}.json'
    texts = texts_for_embedding(chunks)
    signature = str(len(texts)) + '_' + str(sum(len(t) for t in texts))

    if emb_path.exists() and meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding='utf-8'))
            if meta.get('signature') == signature:
                return np.load(emb_path)
        except Exception:
            pass

    model = SentenceTransformer(model_name, cache_folder=str(CACHE_DIR / 'hf_model'))
    arr = model.encode(texts, normalize_embeddings=True, show_progress_bar=True, batch_size=64)
    np.save(emb_path, arr.astype(np.float32))
    meta_path.write_text(json.dumps({'signature': signature}), encoding='utf-8')
    return arr


def dense_search(query: str, embeddings: np.ndarray, model: SentenceTransformer, chunks, k=5) -> List[dict]:
    qv = model.encode([query], normalize_embeddings=True, show_progress_bar=False)[0]
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    normalized = embeddings / norms
    qnorm = np.linalg.norm(qv)
    if qnorm == 0:
        qv = qv
    else:
        qv = qv / qnorm
    scores = normalized @ qv
    idx = np.argsort(scores)[::-1][:k]
    return [{'reference': chunks[int(i)]['reference'], 'score': float(scores[int(i)])} for i in idx]


def rerank_search(query: str, embeddings: np.ndarray, model: SentenceTransformer, chunks, k=5, top=20) -> List[dict]:
    qv = model.encode([query], normalize_embeddings=True, show_progress_bar=False)[0]
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    normalized = embeddings / norms
    qnorm = np.linalg.norm(qv)
    if qnorm == 0:
        qv = qv
    else:
        qv = qv / qnorm
    scores = normalized @ qv
    top_idx = np.argsort(scores)[::-1][:top]
    candidates = [chunks[int(i)]['translation_text'] for i in top_idx]
    ce = CrossEncoder('cross-encoder/ms-marco-MiniLM-L-6-v2', device='cpu')
    pairs = [[query, txt] for txt in candidates]
    rerank_scores = ce.predict(pairs)
    order = np.argsort(rerank_scores)[::-1][:k]
    results = []
    for o in order:
        idx = int(top_idx[o])
        results.append({'reference': chunks[idx]['reference'], 'score': float(rerank_scores[o])})
    return results


def build_bm25(chunks):
    tokenized = [c['translation_text'].lower().split() for c in chunks]
    return BM25Okapi(tokenized)


def hybrid_search(query: str, embeddings: np.ndarray, model: SentenceTransformer, chunks, bm25, k=5, top=20, alpha=0.6):
    # dense top
    qv = model.encode([query], normalize_embeddings=True, show_progress_bar=False)[0]
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    normalized = embeddings / norms
    qnorm = np.linalg.norm(qv)
    if qnorm == 0:
        qv = qv
    else:
        qv = qv / qnorm
    dense_scores = normalized @ qv
    dense_top = np.argsort(dense_scores)[::-1][:top]

    # bm25 top
    bm25_scores = bm25.get_scores(query.lower().split())
    bm25_top = np.argsort(bm25_scores)[::-1][:top]

    # union
    candidates = list(dict.fromkeys(list(dense_top) + list(bm25_top)))
    ds = np.array([float(dense_scores[int(i)]) for i in candidates])
    bs = np.array([float(bm25_scores[int(i)]) for i in candidates])
    # normalize
    if ds.max() - ds.min() > 1e-6:
        nd = (ds - ds.min()) / (ds.max() - ds.min())
    else:
        nd = ds
    if bs.max() - bs.min() > 1e-6:
        nb = (bs - bs.min()) / (bs.max() - bs.min())
    else:
        nb = bs
    combined = alpha * nd + (1 - alpha) * nb
    order = np.argsort(combined)[::-1][:k]
    results = []
    for o in order:
        idx = int(candidates[o])
        results.append({'reference': chunks[idx]['reference'], 'score': float(combined[o])})
    return results


def threshold_search(query: str, embeddings: np.ndarray, model: SentenceTransformer, chunks, k=5, threshold=0.15):
    res = dense_search(query, embeddings, model, chunks, k=k)
    if not res:
        return []
    if res[0]['score'] < threshold:
        return []
    return res


def compute_recall_and_mrr(results: List[dict], expected_refs: List[str]) -> Tuple[float, float]:
    if not expected_refs:
        return 0.0, 0.0
    hits = 0
    first_correct_rank = None
    for rank, item in enumerate(results[:5], start=1):
        ref = item['reference']
        if ref in expected_refs:
            hits += 1
            if first_correct_rank is None:
                first_correct_rank = 1.0 / rank
    recall = hits / len(expected_refs)
    mrr = first_correct_rank if first_correct_rank is not None else 0.0
    return recall, mrr


def run_variant(chunks, eval_data, model_name, variant_name):
    start = time.perf_counter()
    embeddings = load_or_build_embeddings(model_name, chunks)
    model = SentenceTransformer(model_name, cache_folder=str(CACHE_DIR / 'hf_model'))
    build_bm = None
    if variant_name == 'hybrid':
        build_bm = build_bm25(chunks)
    variant_results = []
    total_recall = 0.0
    total_mrr = 0.0
    pos_count = 0
    for query, payload in eval_data.items():
        expected = payload['expected_refs']
        if variant_name == 'dense_default':
            res = dense_search(query, embeddings, model, chunks, k=5)
        elif variant_name == 'rerank':
            res = rerank_search(query, embeddings, model, chunks, k=5, top=20)
        elif variant_name == 'hybrid':
            res = hybrid_search(query, embeddings, model, chunks, build_bm, k=5, top=20)
        elif variant_name == 'mpnet_rerank':
            # use the stronger mpnet embeddings for initial retrieval, then cross-encoder rerank
            res = rerank_search(query, embeddings, model, chunks, k=5, top=20)
        elif variant_name == 'mpnet':
            res = dense_search(query, embeddings, model, chunks, k=5)
        elif variant_name == 'threshold':
            res = threshold_search(query, embeddings, model, chunks, k=5, threshold=0.15)
        else:
            raise ValueError('unknown variant')

        recall, mrr = compute_recall_and_mrr(res, expected)
        if expected:
            total_recall += recall
            total_mrr += mrr
            pos_count += 1
        variant_results.append({'query': query, 'recall@5': recall, 'mrr': mrr, 'top': [r['reference'] for r in res]})

    overall_recall = total_recall / pos_count if pos_count else 0.0
    overall_mrr = total_mrr / pos_count if pos_count else 0.0
    elapsed = time.perf_counter() - start
    return {
        'variant': variant_name,
        'model': model_name,
        'recall@5': overall_recall,
        'mrr': overall_mrr,
        'time_s': elapsed,
        'per_query': variant_results,
    }


def main():
    chunks = load_corpus()
    with EVAL_PATH.open('r', encoding='utf-8') as f:
        eval_data = json.load(f)

    variants = [
        ('sentence-transformers/all-MiniLM-L6-v2', 'dense_default'),
        ('sentence-transformers/all-MiniLM-L6-v2', 'rerank'),
        ('sentence-transformers/all-MiniLM-L6-v2', 'hybrid'),
        ('sentence-transformers/all-mpnet-base-v2', 'mpnet'),
        ('sentence-transformers/all-mpnet-base-v2', 'mpnet_rerank'),
        ('sentence-transformers/all-MiniLM-L6-v2', 'threshold'),
    ]

    results = []
    for model_name, variant in variants:
        print(f'Running variant {variant} with model {model_name}')
        out = run_variant(chunks, eval_data, model_name, variant)
        results.append(out)
        print(f"{variant}: recall@5={out['recall@5']:.3f}, MRR={out['mrr']:.3f}, time={out['time_s']:.1f}s")

    # specific bees query
    bees_query = 'what does the Quran say about bees'
    print('\nBees query top-5 per variant:')
    for out in results:
        model_name = out['model']
        variant = out['variant']
        # rerun top5 for bees more verbosely
        embeddings = load_or_build_embeddings(model_name, chunks)
        model = SentenceTransformer(model_name, cache_folder=str(CACHE_DIR / 'hf_model'))
        if variant == 'dense_default':
            top = dense_search(bees_query, embeddings, model, chunks, k=5)
        elif variant == 'rerank':
            top = rerank_search(bees_query, embeddings, model, chunks, k=5, top=20)
        elif variant == 'hybrid':
            bm25 = build_bm25(chunks)
            top = hybrid_search(bees_query, embeddings, model, chunks, bm25, k=5, top=20)
        elif variant == 'mpnet':
            top = dense_search(bees_query, embeddings, model, chunks, k=5)
        elif variant == 'mpnet_rerank':
            top = rerank_search(bees_query, embeddings, model, chunks, k=5, top=20)
        elif variant == 'threshold':
            top = threshold_search(bees_query, embeddings, model, chunks, k=5, threshold=0.15)
        else:
            top = []
        print(f"{variant} ({model_name}): {[t['reference'] for t in top]}")

    # write results
    with (ROOT / 'variant_sweep_results.json').open('w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
