import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'assets' / 'quran_reader_data.json'
OUT = ROOT / 'backend' / 'corpus.json'


def load_source() -> dict:
    with SOURCE.open('r', encoding='utf-8') as f:
        return json.load(f)


def build_chunks(source: dict) -> list[dict]:
    chunks: list[dict] = []
    for surah in source['surahs']:
        surah_number = int(surah['number'])
        surah_name_english = surah['name_simple']
        surah_name_arabic = surah['name_arabic']
        ayahs = surah['ayahs']
        for index, ayah in enumerate(ayahs):
            verse_number = int(ayah['verse_number'])
            translation_text = ayah['translation']
            arabic_text = ayah['text']
            if not translation_text or not translation_text.strip():
                raise ValueError(
                    f'Empty translation for surah {surah_number}, ayah {verse_number}.'
                )
            if not isinstance(surah_number, int) or not isinstance(verse_number, int):
                raise ValueError(
                    f'Invalid surah:verse reference for surah {surah_number}, ayah {verse_number}.'
                )

            previous_text = ''
            next_text = ''
            if index > 0:
                previous_text = ayahs[index - 1]['translation']
            if index < len(ayahs) - 1:
                next_text = ayahs[index + 1]['translation']

            embedding_parts = [
                f"Surah {surah_name_english}",
            ]
            if previous_text:
                embedding_parts.append(previous_text)
            embedding_parts.append(translation_text)
            if next_text:
                embedding_parts.append(next_text)
            embedding_text = '\n'.join(part for part in embedding_parts if part and part.strip())

            chunks.append(
                {
                    'surah_number': surah_number,
                    'verse_number': verse_number,
                    'surah_name_english': surah_name_english,
                    'surah_name_arabic': surah_name_arabic,
                    'translation_text': translation_text,
                    'arabic_text': arabic_text,
                    'reference': f'{surah_number}:{verse_number}',
                    'context_before': previous_text,
                    'context_after': next_text,
                    'embedding_text': embedding_text,
                }
            )
    return chunks


def validate_chunks(chunks: list[dict]) -> None:
    expected_total = 6236
    if len(chunks) != expected_total:
        raise ValueError(f'Expected {expected_total} chunks, found {len(chunks)}.')

    seen_refs: set[str] = set()
    for chunk in chunks:
        ref = chunk['reference']
        if not ref or ':' not in ref:
            raise ValueError(f'Invalid reference format: {ref!r}')
        surah_number, verse_number = ref.split(':', 1)
        if not surah_number.isdigit() or not verse_number.isdigit():
            raise ValueError(f'Non-numeric reference: {ref!r}')
        if not chunk['translation_text'] or not chunk['translation_text'].strip():
            raise ValueError(f'Empty translation text for reference {ref!r}.')
        if not chunk['embedding_text'] or not chunk['embedding_text'].strip():
            raise ValueError(f'Empty embedding text for reference {ref!r}.')
        if chunk['surah_number'] != int(surah_number) or chunk['verse_number'] != int(verse_number):
            raise ValueError(
                f'Reference mismatch for chunk: {ref!r} '
                f'(stored as surah {chunk["surah_number"]}, verse {chunk["verse_number"]}).'
            )
        seen_refs.add(ref)

    source_pairs = set()
    source = load_source()
    for surah in source['surahs']:
        for ayah in surah['ayahs']:
            source_pairs.add(f"{surah['number']}:{ayah['verse_number']}")

    if seen_refs != source_pairs:
        missing = sorted(source_pairs - seen_refs)
        extra = sorted(seen_refs - source_pairs)
        raise ValueError(
            f'Reference set mismatch: missing={missing[:10]} extra={extra[:10]} '
            f'(total missing={len(missing)}, total extra={len(extra)})'
        )

    if len(seen_refs) != len(chunks):
        raise ValueError('Duplicate references detected in corpus chunks.')


def print_samples(chunks: list[dict]) -> None:
    sample_refs = ['1:1', '2:255', '114:6']
    for ref in sample_refs:
        target = next(chunk for chunk in chunks if chunk['reference'] == ref)
        print(f'{ref} -> {target}')


if __name__ == '__main__':
    source = load_source()
    chunks = build_chunks(source)
    validate_chunks(chunks)
    with OUT.open('w', encoding='utf-8') as f:
        json.dump(chunks, f, ensure_ascii=False, indent=2)
    print(f'Corpus chunks written: {len(chunks)}')
    print_samples(chunks)
