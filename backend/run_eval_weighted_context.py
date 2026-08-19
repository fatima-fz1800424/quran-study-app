import json
from pathlib import Path

import numpy as np
from sentence_transformers import SentenceTransformer

ROOT = Path(__file__).resolve().parent.parent
CORPUS_PATH = ROOT / 'backend' / 'corpus.json'
EVAL_PATH = ROOT / 'backend' / 'eval_queries.json'
MODEL_NAME = 'all-MiniLM-L6-v2'


def parse_ref(ref: str) -> tuple[int, int]:
    surah_str, verse_str = ref.split(':', 1)
    return int(surah_str), int(verse_str)


def ref_is_expected(ref: str, expected_refs: list[str]) -> bool:
    ref_pair = parse_ref(ref)
    for expected in expected_refs:
        if '-' in expected:
            start_ref, end_ref = expected.split('-', 1)
            start_pair = parse_ref(start_ref)
            end_pair = parse_ref(end_ref)
            if start_pair <= ref_pair <= end_pair:
                return True
        else:
            if parse_ref(expected) == ref_pair:
                return True
    return False


def compute_recall_and_mrr(results: list[dict], expected_refs: list[str]) -> tuple[float, float]:
    if not expected_refs:
        return 0.0, 0.0

    first_correct = None
    hits = 0

    for rank, item in enumerate(results[:5], start=1):
        if ref_is_expected(item['reference'], expected_refs):
            hits += 1
            if first_correct is None:
                first_correct = 1 / rank

    recall = hits / len(expected_refs)
    mrr = first_correct if first_correct is not None else 0.0
    return recall, mrr


def main() -> None:
    with CORPUS_PATH.open('r', encoding='utf-8') as f:
        corpus = json.load(f)
    with EVAL_PATH.open('r', encoding='utf-8') as f:
        eval_data = json.load(f)

    model = SentenceTransformer(
        MODEL_NAME,
        cache_folder=str(ROOT / 'backend' / '.retrieval_cache' / 'hf_model'),
    )

    texts = []
    for chunk in corpus:
        current = chunk['translation_text']
        before = chunk.get('context_before', '')
        after = chunk.get('context_after', '')
        texts.append(
            f"Surah {chunk['surah_name_english']}\n{current}\n{current}\n{before}\n{after}"
        )

    embeddings = model.encode(
        texts,
        normalize_embeddings=True,
        show_progress_bar=False,
        batch_size=64,
    )

    per_query = []
    overall_recall = 0.0
    overall_mrr = 0.0
    positive_count = 0

    for query, payload in eval_data.items():
        expected_refs = payload['expected_refs']
        if not expected_refs:
            query_vector = model.encode([query], normalize_embeddings=True, show_progress_bar=False)[0]
            query_vector = query_vector / np.linalg.norm(query_vector)
            scores = embeddings @ query_vector
            order = np.argsort(scores)[::-1][:5]
            top_refs = [corpus[int(index)]['reference'] for index in order]
            print(f"{query}: negative case; top results = {top_refs}")
            continue

        query_vector = model.encode([query], normalize_embeddings=True, show_progress_bar=False)[0]
        query_vector = query_vector / np.linalg.norm(query_vector)
        scores = embeddings @ query_vector
        order = np.argsort(scores)[::-1][:5]

        results = [
            {
                'reference': corpus[int(index)]['reference'],
                'score': float(scores[int(index)]),
            }
            for index in order
        ]
        recall, mrr = compute_recall_and_mrr(results, expected_refs)
        overall_recall += recall
        overall_mrr += mrr
        positive_count += 1
        per_query.append((query, recall, mrr))
        print(f"{query}: recall@5={recall:.3f}, MRR={mrr:.3f}")

    overall_recall /= positive_count
    overall_mrr /= positive_count
    print(f"OVERALL: recall@5={overall_recall:.3f}, MRR={overall_mrr:.3f}")


if __name__ == '__main__':
    main()
