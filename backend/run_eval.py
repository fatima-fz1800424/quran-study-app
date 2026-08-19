import json
from pathlib import Path

from fastapi.testclient import TestClient

from app import app

ROOT = Path(__file__).resolve().parent.parent
EVAL_PATH = ROOT / 'backend' / 'eval_queries.json'


def parse_ref(value: str) -> tuple[int, int]:
    surah_str, verse_str = value.split(':', 1)
    return int(surah_str), int(verse_str)


def range_covered(ref: str, expected: list[str]) -> bool:
    if '-' in ref:
        start, end = ref.split('-', 1)
        start_pair = parse_ref(start)
        end_pair = parse_ref(end)
        target_pairs = set()
        for surah in range(start_pair[0], end_pair[0] + 1):
            if surah == start_pair[0] == end_pair[0]:
                target_pairs.update({(surah, verse) for verse in range(start_pair[1], end_pair[1] + 1)})
            elif surah == start_pair[0]:
                target_pairs.update({(surah, verse) for verse in range(start_pair[1], 1000)})
            elif surah == end_pair[0]:
                target_pairs.update({(surah, verse) for verse in range(1, end_pair[1] + 1)})
            else:
                target_pairs.update({(surah, verse) for verse in range(1, 1000)})
        for expected_ref in expected:
            if '-' in expected_ref:
                expected_start, expected_end = expected_ref.split('-', 1)
                e_start = parse_ref(expected_start)
                e_end = parse_ref(expected_end)
                for pair in target_pairs:
                    if e_start <= pair <= e_end:
                        return True
                continue
            p = parse_ref(expected_ref)
            if p in target_pairs:
                return True
        return False

    ref_pair = parse_ref(ref)
    for expected_ref in expected:
        if '-' in expected_ref:
            expected_start, expected_end = expected_ref.split('-', 1)
            e_start = parse_ref(expected_start)
            e_end = parse_ref(expected_end)
            if e_start <= ref_pair <= e_end:
                return True
            continue
        if parse_ref(expected_ref) == ref_pair:
            return True
    return False


def compute_recall_and_mrr(query_results: list[dict], expected_refs: list[str]) -> tuple[float, float]:
    if not expected_refs:
        return 0.0, 0.0

    hits = 0
    top_hits: set[str] = set()
    first_correct_rank = None

    for rank, item in enumerate(query_results[:5], start=1):
        ref = item['reference']
        if ref in expected_refs or range_covered(ref, expected_refs):
            if ref not in top_hits:
                top_hits.add(ref)
            hits += 1
            if first_correct_rank is None:
                first_correct_rank = 1 / rank

    recall = hits / len(expected_refs)
    mrr = first_correct_rank if first_correct_rank is not None else 0.0
    return recall, mrr


def evaluate_strategy(strategy: str, model_name: str | None = None, threshold: float | None = None) -> tuple[float, float, list[dict]]:
    with EVAL_PATH.open('r', encoding='utf-8') as f:
        eval_data = json.load(f)

    client = TestClient(app)
    total_recall = 0.0
    total_mrr = 0.0
    positive_count = 0
    per_query = []

    for query, payload in eval_data.items():
        expected_refs = payload['expected_refs']
        params = {'q': query, 'k': 5, 'strategy': strategy}
        if threshold is not None:
            params['threshold'] = threshold
        if model_name is not None:
            params['model_name'] = model_name
        if not expected_refs:
            response = client.get('/search', params=params)
            response.raise_for_status()
            results = response.json()
            print(f"{strategy} | {query}: negative case; top results = {[item['reference'] for item in results[:5]]}")
            continue

        response = client.get('/search', params=params)
        response.raise_for_status()
        results = response.json()
        recall, mrr = compute_recall_and_mrr(results, expected_refs)
        total_recall += recall
        total_mrr += mrr
        positive_count += 1
        per_query.append({'query': query, 'expected_refs': expected_refs, 'recall@5': recall, 'mrr': mrr})
        print(f"{strategy} | {query}: recall@5={recall:.3f}, MRR={mrr:.3f}")

    overall_recall = total_recall / positive_count if positive_count else 0.0
    overall_mrr = total_mrr / positive_count if positive_count else 0.0
    print(f"{strategy} | OVERALL: recall@5={overall_recall:.3f}, MRR={overall_mrr:.3f}")
    return overall_recall, overall_mrr, per_query


def main() -> None:
    variants = [
        ('dense', None, None),
        ('rerank', None, None),
        ('hybrid', None, None),
        ('dense', 'all-mpnet-base-v2', None),
        ('dense', None, 0.25),
    ]
    for strategy, model_name, threshold in variants:
        evaluate_strategy(strategy=strategy, model_name=model_name, threshold=threshold)
        print('---')


if __name__ == '__main__':
    main()
