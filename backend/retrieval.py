import hashlib
import json
import logging
import re
import time
from pathlib import Path

import numpy as np
from rank_bm25 import BM25Okapi
from sentence_transformers import CrossEncoder, SentenceTransformer

ROOT = Path(__file__).resolve().parent.parent
CORPUS_PATH = ROOT / 'backend' / 'corpus.json'
CACHE_DIR = ROOT / 'backend' / '.retrieval_cache'
MODEL_NAME = 'all-MiniLM-L6-v2'
RERANK_MODEL_NAME = 'cross-encoder/ms-marco-MiniLM-L-6-v2'

logger = logging.getLogger(__name__)


def _tokenize(text: str) -> list[str]:
    return re.findall(r"\w+", (text or '').lower())


def _normalize_rows(matrix: np.ndarray) -> np.ndarray:
    """Scale each row to unit length, leaving all-zero rows alone."""
    norms = np.linalg.norm(matrix, axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    return (matrix / norms).astype(np.float32)


class QuranRetriever:
    def __init__(self) -> None:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        self.model = None
        self.cross_encoder = None
        self.bm25_index = None
        self.chunks: list[dict] = []
        self.embeddings: np.ndarray | None = None
        self.model_name = MODEL_NAME

    def initialize(self, model_name: str | None = None) -> None:
        requested = model_name or self.model_name

        # A different model needs its own weights and its own embeddings. This
        # used to return early whenever anything was loaded, which silently
        # served results from whichever model happened to load first.
        already_loaded = (
            self.model is not None
            and self.embeddings is not None
            and getattr(self, '_loaded_model_name', None) == requested
        )
        if already_loaded:
            self.model_name = requested
            return

        if self.model is not None and getattr(self, '_loaded_model_name', None) != requested:
            logger.info(
                'Retriever: switching model from %s to %s; reloading embeddings',
                getattr(self, '_loaded_model_name', None),
                requested,
            )
            self.model = None
            self.embeddings = None
            self.bm25_index = None

        self.model_name = requested

        total_start = time.perf_counter()
        logger.info('Retriever startup: loading corpus...')
        corpus_start = time.perf_counter()
        self.chunks = self._load_chunks()
        logger.info('Retriever startup: corpus loaded in %.2fs', time.perf_counter() - corpus_start)

        logger.info('Retriever startup: loading sentence-transformer model %s...', self.model_name)
        model_start = time.perf_counter()
        if self.model is None or self.model_name != getattr(self, '_loaded_model_name', None):
            self.model = SentenceTransformer(
                self.model_name,
                cache_folder=str(CACHE_DIR / 'hf_model'),
            )
            self._loaded_model_name = self.model_name
        logger.info('Retriever startup: model loaded in %.2fs', time.perf_counter() - model_start)

        logger.info('Retriever startup: building or loading embeddings...')
        embeddings_start = time.perf_counter()
        # Normalise once, here. Every query previously renormalised the whole
        # 6236x768 matrix before its dot product, which cost ~40ms per request
        # to reproduce a result that does not change between requests.
        self.embeddings = _normalize_rows(self._load_or_build_embeddings())
        logger.info('Retriever startup: embeddings ready in %.2fs', time.perf_counter() - embeddings_start)
        logger.info('Retriever startup: complete in %.2fs', time.perf_counter() - total_start)

    def _load_chunks(self) -> list[dict]:
        with CORPUS_PATH.open('r', encoding='utf-8') as f:
            return json.load(f)

    def _load_or_build_embeddings(self) -> np.ndarray:
        texts = [chunk['embedding_text'] for chunk in self.chunks]
        signature = hashlib.sha256(
            ('\n'.join(texts) + f'\nmodel={self.model_name}').encode('utf-8')
        ).hexdigest()

        embeddings_path = CACHE_DIR / f'embeddings_{self.model_name.replace("/", "_")}.npy'
        metadata_path = CACHE_DIR / f'metadata_{self.model_name.replace("/", "_")}.json'

        if embeddings_path.exists() and metadata_path.exists():
            embeddings = np.load(embeddings_path)
            cached_metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
            if isinstance(cached_metadata, dict):
                if cached_metadata.get('signature') == signature and len(cached_metadata.get('references', [])) == len(self.chunks):
                    return embeddings.astype(np.float32)

        embeddings = self.model.encode(
            texts,
            normalize_embeddings=True,
            show_progress_bar=False,
            batch_size=64,
        )
        np.save(embeddings_path, embeddings.astype(np.float32))
        metadata_path.write_text(
            json.dumps(
                {
                    'signature': signature,
                    'references': [chunk['reference'] for chunk in self.chunks],
                    'model_name': self.model_name,
                },
                ensure_ascii=False,
            ),
            encoding='utf-8',
        )
        return embeddings.astype(np.float32)

    def _dense_scores(self, query: str) -> np.ndarray:
        if self.model is None or self.embeddings is None:
            self.initialize()

        query_vector = self.model.encode(
            [query],
            normalize_embeddings=True,
            show_progress_bar=False,
            batch_size=1,
        )[0]

        # self.embeddings is already row-normalised at load time, so only the
        # query vector needs scaling here.
        query_norm = np.linalg.norm(query_vector)
        if query_norm != 0:
            query_vector = query_vector / query_norm

        return self.embeddings @ query_vector

    def _format_result(self, chunk: dict, score: float) -> dict:
        return {
            'reference': chunk['reference'],
            'score': float(score),
            'surah_number': chunk['surah_number'],
            'verse_number': chunk['verse_number'],
            'surah_name_english': chunk['surah_name_english'],
            'translation_text': chunk['translation_text'],
            'context_before': chunk.get('context_before', ''),
            'context_after': chunk.get('context_after', ''),
        }

    def _rerank(self, query: str, candidates: list[dict], top_n: int = 20) -> list[dict]:
        if self.cross_encoder is None:
            self.cross_encoder = CrossEncoder(RERANK_MODEL_NAME, max_length=512)

        pairs = [
            (query, candidate.get('embedding_text') or candidate.get('translation_text', ''))
            for candidate in candidates[:top_n]
        ]
        if not pairs:
            return []
        rerank_scores = self.cross_encoder.predict(pairs)
        ranked = sorted(
            zip(candidates[:top_n], rerank_scores),
            key=lambda item: float(item[1]),
            reverse=True,
        )
        return [self._format_result(chunk, score) for chunk, score in ranked]

    def _hybrid(self, query: str, dense_scores: np.ndarray, k: int = 5, alpha: float = 0.7, beta: float = 0.3) -> list[dict]:
        if self.bm25_index is None:
            corpus_tokens = [_tokenize(chunk.get('translation_text') or chunk.get('embedding_text') or '') for chunk in self.chunks]
            self.bm25_index = BM25Okapi(corpus_tokens)

        query_tokens = _tokenize(query)
        if not query_tokens:
            return []
        bm25_scores = self.bm25_index.get_scores(query_tokens)

        # take top candidates from both dense and bm25 then union them
        dense_top = np.argsort(dense_scores)[::-1][:50]
        bm25_top = np.argsort(bm25_scores)[::-1][:50]

        candidate_indices = list(dict.fromkeys(list(dense_top) + list(bm25_top)))

        dense_candidate_scores = np.array([float(dense_scores[int(i)]) for i in candidate_indices])
        bm25_candidate_scores = np.array([float(bm25_scores[int(i)]) for i in candidate_indices])

        # normalize to comparable 0-1 ranges before fusion
        if dense_candidate_scores.size and dense_candidate_scores.max() - dense_candidate_scores.min() > 1e-6:
            dense_norm = (dense_candidate_scores - dense_candidate_scores.min()) / (dense_candidate_scores.max() - dense_candidate_scores.min())
        else:
            dense_norm = dense_candidate_scores

        if bm25_candidate_scores.size and bm25_candidate_scores.max() - bm25_candidate_scores.min() > 1e-6:
            bm25_norm = (bm25_candidate_scores - bm25_candidate_scores.min()) / (bm25_candidate_scores.max() - bm25_candidate_scores.min())
        else:
            bm25_norm = bm25_candidate_scores

        combined = []
        for i, idx in enumerate(candidate_indices):
            combined_score = float(alpha * dense_norm[i] + beta * bm25_norm[i])
            combined.append((int(idx), combined_score))

        combined.sort(key=lambda pair: pair[1], reverse=True)
        results: list[dict] = []
        for idx, combined_score in combined[:k]:
            chunk = self.chunks[idx]
            results.append(self._format_result(chunk, combined_score))
        return results

    def search(self, query: str, k: int = 5, strategy: str = 'dense', rerank_top_n: int = 20, threshold: float | None = None, model_name: str | None = None) -> list[dict]:
        if model_name is not None:
            self.model_name = model_name
        if self.model is None or self.embeddings is None:
            self.initialize(model_name=self.model_name)
        if not query or not query.strip():
            raise ValueError('Query must not be empty.')

        strategy = (strategy or 'dense').lower()
        k = max(1, min(k, len(self.chunks)))
        dense_scores = self._dense_scores(query)
        if strategy == 'rerank':
            candidate_indices = np.argsort(dense_scores)[::-1][:max(rerank_top_n, k)]
            candidates = [self.chunks[int(idx)] for idx in candidate_indices]
            results = self._rerank(query, candidates, top_n=rerank_top_n)
        elif strategy == 'hybrid':
            results = self._hybrid(query, dense_scores, k=k)
        else:
            top_indices = np.argsort(dense_scores)[::-1][:k]
            results = [self._format_result(self.chunks[int(idx)], float(dense_scores[int(idx)])) for idx in top_indices]

        if threshold is not None:
            results = [result for result in results if float(result['score']) >= float(threshold)]
            if not results:
                return []

        return results[:k]

    def get_related(
        self,
        surah: int,
        verse: int,
        k: int = 5,
        model_name: str | None = None,
        max_same_surah: int | None = None,
        min_score: float | None = None,
        rerank: bool = False,
        rerank_top_n: int = 20,
        same_surah_penalty: float = 0.03,
        cross_surah_gate_score: float | None = None,
    ) -> list[dict]:
        """Return the top-k most similar verses to the given surah:verse using embeddings.

        Excludes the verse itself and immediate neighbours (previous 2 and next 2 verses in the same surah).
        Supports optional same-surah capping, minimum-score filtering, and optional cross-encoder reranking.

        Selection rules, applied in order:
        - Same-surah candidates are penalised by `same_surah_penalty`, and all
          ranking and filtering below uses that adjusted score.
        - Cross-surah gate: unless some cross-surah candidate scores at least
          `cross_surah_gate_score`, return nothing. A verse whose only matches
          sit inside its own surah is treated as surah-level topical bleed
          rather than as having genuine thematic links.
        - Candidates below `min_score` are then dropped.
        - Return the top `k` by adjusted score, drawn from both cross-surah and
          same-surah candidates, with at most `max_same_surah` verses from the
          target's own surah.

        The gate and the display threshold are deliberately separate. The gate
        asks whether this verse resonates outside its own surah at all, which is
        a weaker question than whether a given match is strong enough to show;
        so `cross_surah_gate_score` is normally set lower than `min_score`. That
        lets a verse with one strong same-surah match still surface it, provided
        the verse has some cross-surah resonance, while a verse with no reach
        beyond its own surah returns nothing. When `cross_surah_gate_score` is
        None it falls back to `min_score`, making the two questions identical.

        `max_same_surah` caps only verses from the target's own surah. It does
        not limit how many verses may come from any other single surah.
        """
        if model_name is None:
            model_name = 'sentence-transformers/all-mpnet-base-v2'

        # ensure the requested model/embeddings are loaded
        self.initialize(model_name=model_name)

        # find the target index
        target_idx = None
        for i, chunk in enumerate(self.chunks):
            try:
                s = int(chunk.get('surah_number'))
                v = int(chunk.get('verse_number'))
            except Exception:
                continue
            if s == int(surah) and v == int(verse):
                target_idx = i
                target_surah = s
                target_verse = v
                break

        if target_idx is None:
            raise ValueError(f'Verse {surah}:{verse} not found in corpus')

        # Already row-normalised at load time; no need to redo it per call.
        normalized = self.embeddings
        target_vec = normalized[target_idx]
        # similarity scores
        scores = normalized @ target_vec

        # build exclusion set: same surah and verse within +/-2
        exclude = set()
        for i, chunk in enumerate(self.chunks):
            try:
                s = int(chunk.get('surah_number'))
                v = int(chunk.get('verse_number'))
            except Exception:
                continue
            if s == target_surah and abs(v - target_verse) <= 2:
                exclude.add(i)

        # candidate indices excluding neighbours
        candidate_indices = [i for i in range(len(scores)) if i not in exclude]
        if not candidate_indices:
            return []

        # build candidates with adjusted score (apply same-surah penalty)
        candidates = []
        for i in candidate_indices:
            orig = float(scores[int(i)])
            s = int(self.chunks[int(i)].get('surah_number', -1))
            adjusted = orig - (float(same_surah_penalty) if s == target_surah else 0.0)
            candidates.append((int(i), orig, adjusted, s))

        # sort by adjusted score desc (we penalize same-surah before ordering)
        candidates.sort(key=lambda x: x[2], reverse=True)

        # rerank if requested: take top rerank_top_n by adjusted score and rerank using cross-encoder
        if rerank:
            top_for_rerank = candidates[:max(1, rerank_top_n)]
            chunks_for_rerank = [self.chunks[c[0]] for c in top_for_rerank]
            # use the target verse text as the rerank query
            query_text = self.chunks[target_idx].get('embedding_text') or self.chunks[target_idx].get('translation_text', '')
            reranked = self._rerank(query_text, chunks_for_rerank, top_n=len(chunks_for_rerank))
            # _rerank returns formatted dicts with score; map back to indices via reference
            ref_to_idx = {chunk['reference']: i for i, chunk in enumerate(self.chunks)}
            new_candidates = []
            for item in reranked:
                ref = item['reference']
                idx = ref_to_idx.get(ref)
                if idx is not None and idx not in exclude:
                    # set both orig and adjusted to the rerank score for ordering/filtering
                    new_candidates.append((int(idx), float(item['score']), float(item['score']), int(self.chunks[int(idx)].get('surah_number', -1))))
            candidates = new_candidates

        # Cross-surah gate. Evaluated before the display threshold, and against
        # the gate score rather than min_score, so that asking "does this verse
        # reach outside its own surah at all" stays a weaker test than asking
        # "is this match strong enough to show".
        gate_score = cross_surah_gate_score if cross_surah_gate_score is not None else min_score
        cross_surah = [c for c in candidates if c[3] != target_surah]
        if gate_score is not None:
            cross_surah = [c for c in cross_surah if c[2] >= float(gate_score)]
        if not cross_surah:
            return []

        # apply minimum score threshold on adjusted score if requested (after rerank if used)
        if min_score is not None:
            candidates = [c for c in candidates if c[2] >= float(min_score)]

        if not candidates:
            return []

        # The gate is passed, so rank cross-surah and same-surah candidates
        # together by adjusted score and take the top k, allowing at most
        # `max_same_surah` verses from the target's own surah. The cap is a hard
        # limit: once it is reached, further same-surah candidates are skipped
        # and the slots go to the next best cross-surah verses, or go unfilled.
        top_results: list[dict] = []
        selected: list[tuple[int, float, float, int]] = []
        same_surah_used = 0
        for candidate in candidates:  # already ordered by adjusted score
            if candidate[3] == target_surah:
                if max_same_surah is not None and same_surah_used >= int(max_same_surah):
                    continue
                same_surah_used += 1
            selected.append(candidate)
            if len(selected) >= k:
                break

        for idx, orig, adjusted, s in selected[:k]:
            chunk = self.chunks[idx]
            top_results.append({
                'reference': chunk.get('reference'),
                'surah_number': int(chunk.get('surah_number')),
                'verse_number': int(chunk.get('verse_number')),
                'arabic_text': chunk.get('arabic_text', ''),
                'translation_text': chunk.get('translation_text', ''),
                'score': float(orig),
                'adjusted_score': float(adjusted),
            })

        return top_results


retriever = QuranRetriever()
