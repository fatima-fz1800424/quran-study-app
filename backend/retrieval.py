import hashlib
import json
from pathlib import Path

import numpy as np
from sentence_transformers import SentenceTransformer

ROOT = Path(__file__).resolve().parent.parent
CORPUS_PATH = ROOT / 'backend' / 'corpus.json'
CACHE_DIR = ROOT / 'backend' / '.retrieval_cache'
EMBEDDINGS_PATH = CACHE_DIR / 'embeddings.npy'
METADATA_PATH = CACHE_DIR / 'metadata.json'
MODEL_NAME = 'all-MiniLM-L6-v2'


class QuranRetriever:
    def __init__(self) -> None:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        self.model = SentenceTransformer(
            MODEL_NAME,
            cache_folder=str(CACHE_DIR / 'hf_model'),
        )
        self.chunks = self._load_chunks()
        self.embeddings = self._load_or_build_embeddings()

    def _load_chunks(self) -> list[dict]:
        with CORPUS_PATH.open('r', encoding='utf-8') as f:
            return json.load(f)

    def _load_or_build_embeddings(self) -> np.ndarray:
        texts = [chunk['embedding_text'] for chunk in self.chunks]
        signature = hashlib.sha256(
            ('\n'.join(texts)).encode('utf-8')
        ).hexdigest()

        if EMBEDDINGS_PATH.exists() and METADATA_PATH.exists():
            embeddings = np.load(EMBEDDINGS_PATH)
            cached_metadata = json.loads(METADATA_PATH.read_text(encoding='utf-8'))
            if isinstance(cached_metadata, dict):
                if cached_metadata.get('signature') == signature and len(cached_metadata.get('references', [])) == len(self.chunks):
                    return embeddings.astype(np.float32)
            else:
                # Older cache files stored a plain list of references; rebuild to match the current embedding text schema.
                pass

        embeddings = self.model.encode(
            texts,
            normalize_embeddings=True,
            show_progress_bar=False,
            batch_size=64,
        )
        np.save(EMBEDDINGS_PATH, embeddings.astype(np.float32))
        METADATA_PATH.write_text(
            json.dumps(
                {
                    'signature': signature,
                    'references': [chunk['reference'] for chunk in self.chunks],
                },
                ensure_ascii=False,
            ),
            encoding='utf-8',
        )
        return embeddings.astype(np.float32)

    def search(self, query: str, k: int = 5) -> list[dict]:
        if not query or not query.strip():
            raise ValueError('Query must not be empty.')
        k = max(1, min(k, len(self.chunks)))

        query_vector = self.model.encode(
            [query],
            normalize_embeddings=True,
            show_progress_bar=False,
            batch_size=1,
        )[0]

        norm = np.linalg.norm(self.embeddings, axis=1, keepdims=True)
        norm = np.where(norm == 0, 1.0, norm)
        normalized_embeddings = self.embeddings / norm
        query_norm = np.linalg.norm(query_vector)
        if query_norm == 0:
            query_vector = query_vector / 1.0
        else:
            query_vector = query_vector / query_norm

        scores = normalized_embeddings @ query_vector
        top_indices = np.argsort(scores)[::-1][:k]

        results: list[dict] = []
        for idx in top_indices:
            chunk = self.chunks[int(idx)]
            results.append(
                {
                    'reference': chunk['reference'],
                    'score': float(scores[int(idx)]),
                    'surah_number': chunk['surah_number'],
                    'verse_number': chunk['verse_number'],
                    'surah_name_english': chunk['surah_name_english'],
                    'translation_text': chunk['translation_text'],
                    'context_before': chunk.get('context_before', ''),
                    'context_after': chunk.get('context_after', ''),
                }
            )
        return results


retriever = QuranRetriever()
