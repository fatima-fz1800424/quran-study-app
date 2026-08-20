"""Build assets/quran_reader_data.json from Tanzil sources.

Everything the app stores comes from Tanzil, whose terms permit exactly that:

    "Permission is granted to copy and distribute verbatim copies of the Quran
    text provided here, but changing the text is not allowed. The text can be
    used in any website or application, provided that its source (Tanzil
    Project) is clearly indicated, and a link is made to tanzil.net to enable
    users to keep track of changes."

The Quran Foundation chapters endpoint is still called, but only as an
independent cross-check of the per-surah ayah counts. Nothing from it is
written to disk: their developer terms forbid storing their content for more
than a week, which is incompatible with a bundled offline corpus. See
docs/DECISIONS.md.

Run from the repository root:

    python tool/build_quran_assets.py
"""

import json
import re
import unicodedata
import urllib.request
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets'

# Uthmani text, one "surah|ayah|text" line per ayah. The annotation options are
# enabled so the text carries the pause marks, sajdah and rub-el-hizb signs and
# tatweel a printed mushaf shows.
ARABIC_URL = (
    'https://tanzil.net/pub/download/index.php'
    '?quranType=uthmani&outType=txt-2'
    '&marks=true&sajdah=true&rub=true&tatweel=true&agree=true'
)
# Surah metadata: [start, ayas, order, rukus, name, tname, ename, type].
# Header states: Copyright (C) 2008-2009 Tanzil.info, CC Attribution 3.0.
METADATA_URL = 'https://tanzil.net/res/text/metadata/quran-data.js'
TRANSLATION_URL = 'https://tanzil.net/trans/en.yusufali?type=xml'
# Cross-check only. Never stored.
QF_CHAPTERS_URL = 'https://api.quran.com/api/v4/chapters?language=en'

EXPECTED_SURAHS = 114
EXPECTED_AYAHS = 6236

# Mirrors kMuqattaatExceptions in lib/data/quran_corpus_validator.dart: these
# openings are bare disconnected letters and carry no diacritic.
MUQATTAAT_EXCEPTIONS = {
    '2:1', '3:1', '7:1', '19:1', '20:1', '26:1', '28:1', '29:1', '30:1',
    '31:1', '32:1', '36:1', '40:1', '41:1', '42:1', '42:2', '43:1', '44:1',
    '45:1', '46:1',
}

DIACRITICS = {chr(c) for c in range(0x064B, 0x0653)}
# Marks stripped only to recognise the basmala prefix, never from stored text.
SKELETON_STRIP = {'ـ'} | {chr(c) for c in range(0x064B, 0x0659)} | {'ٰ'}

# Surahs 1 and 9 are the exceptions: in al-Fatihah the basmala is verse 1, and
# at-Tawbah has none.
NO_LEADING_BASMALA = {1, 9}


def fetch(url: str, *, binary: bool = False):
    request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(request, timeout=120) as response:
        raw = response.read()
    return raw if binary else raw.decode('utf-8')


def skeleton(text: str) -> str:
    return ''.join(c for c in text if c not in SKELETON_STRIP)


def parse_arabic(payload: str) -> dict[tuple[int, int], str]:
    verses = {}
    for line in payload.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split('|', 2)
        if len(parts) != 3:
            continue
        verses[(int(parts[0]), int(parts[1]))] = parts[2]
    return verses


def parse_metadata(payload: str) -> dict[int, dict]:
    match = re.search(r'QuranData\.Sura\s*=\s*\[(.*?)\n\];', payload, re.DOTALL)
    if match is None:
        raise ValueError('Could not locate QuranData.Sura in the Tanzil metadata.')

    row = re.compile(
        r'\[\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,'
        r"\s*['\"](.*?)['\"]\s*,\s*['\"](.*?)['\"]\s*,"
        r"\s*['\"](.*?)['\"]\s*,\s*['\"](.*?)['\"]\s*\]"
    )
    surahs = {}
    for index, found in enumerate(row.finditer(match.group(1)), start=1):
        _start, ayas, _order, _rukus, name, tname, ename, kind = found.groups()
        surahs[index] = {
            'name_arabic': name,
            'name_transliterated': tname,
            'name_english': ename,
            'verse_count': int(ayas),
            # Preserve the vocabulary the app already used for these values.
            'revelation_place': {'Meccan': 'makkah', 'Medinan': 'madinah'}[kind],
        }
    return surahs


def parse_translation(payload: str) -> tuple[str, dict[tuple[int, int], str]]:
    comment = re.search(r'<!--(.*?)-->', payload, flags=re.DOTALL)
    if comment is None:
        raise ValueError('Missing Tanzil attribution header in the translation XML.')
    attribution = comment.group(1).strip()

    root = ET.fromstring(payload.replace(comment.group(0), '', 1))
    verses = {}
    for sura in root.findall('sura'):
        surah_number = int(sura.get('index'))
        for aya in sura.findall('aya'):
            text = aya.get('text')
            if text is None:
                raise ValueError(f'Missing translation text in surah {surah_number}.')
            verses[(surah_number, int(aya.get('index')))] = text
    return attribution, verses


def validate_arabic(text: str, verse_key: str) -> None:
    """Mirror of validateArabicAyahText in the Dart validator."""
    trimmed = text.strip()
    if not trimmed:
        raise ValueError(f'{verse_key}: ayah text is empty.')
    if not (set(trimmed) & DIACRITICS) and verse_key not in MUQATTAAT_EXCEPTIONS:
        raise ValueError(f'{verse_key}: no Arabic diacritic, and not a known muqatta’at opening.')
    if re.search(r'[A-Za-z]', trimmed):
        raise ValueError(f'{verse_key}: contains Latin letters.')


def main() -> None:
    print('Fetching Tanzil Uthmani text...')
    arabic = parse_arabic(fetch(ARABIC_URL))
    print('Fetching Tanzil surah metadata...')
    metadata = parse_metadata(fetch(METADATA_URL))
    print('Fetching Tanzil Yusuf Ali translation...')
    attribution, translation = parse_translation(fetch(TRANSLATION_URL))
    print('Fetching Quran Foundation chapter counts (cross-check only)...')
    qf_counts = {
        int(chapter['id']): int(chapter['verses_count'])
        for chapter in json.loads(fetch(QF_CHAPTERS_URL))['chapters']
    }

    # --- structural checks -------------------------------------------------
    if len(metadata) != EXPECTED_SURAHS:
        raise ValueError(f'Expected {EXPECTED_SURAHS} surahs, parsed {len(metadata)}.')
    if len(arabic) != EXPECTED_AYAHS:
        raise ValueError(f'Expected {EXPECTED_AYAHS} ayahs, parsed {len(arabic)}.')
    if len(translation) != EXPECTED_AYAHS:
        raise ValueError(f'Expected {EXPECTED_AYAHS} translations, parsed {len(translation)}.')
    if len(qf_counts) != EXPECTED_SURAHS:
        raise ValueError(f'Cross-check source returned {len(qf_counts)} chapters.')

    observed = Counter(surah for surah, _ in arabic)
    for number, meta in sorted(metadata.items()):
        for label, expected in (('Tanzil metadata', meta['verse_count']),
                                ('Quran Foundation', qf_counts[number])):
            if observed[number] != expected:
                raise ValueError(
                    f'Surah {number}: {label} says {expected} ayahs, '
                    f'text has {observed[number]}.'
                )

    # --- basmala separation ------------------------------------------------
    # Tanzil's line format prepends the basmala to verse 1 of every surah that
    # opens with one. It is kept, not discarded: stored per surah exactly as
    # Tanzil wrote it, so the corpus still holds every character of their text.
    basmala_skeleton = skeleton(arabic[(1, 1)])
    basmalas: dict[int, str] = {}
    for number in metadata:
        if number in NO_LEADING_BASMALA:
            continue
        words = arabic[(number, 1)].split()
        if len(words) > 4 and skeleton(' '.join(words[:4])) == basmala_skeleton:
            basmalas[number] = ' '.join(words[:4])
            arabic[(number, 1)] = ' '.join(words[4:])
        else:
            raise ValueError(f'Surah {number}: expected a leading basmala on verse 1.')

    expected_basmalas = EXPECTED_SURAHS - len(NO_LEADING_BASMALA)
    if len(basmalas) != expected_basmalas:
        raise ValueError(f'Separated {len(basmalas)} basmalas, expected {expected_basmalas}.')

    # --- per-ayah checks ---------------------------------------------------
    for (surah, verse), text in sorted(arabic.items()):
        validate_arabic(text, f'{surah}:{verse}')
    for key, text in translation.items():
        if not text.strip():
            raise ValueError(f'{key}: empty translation.')
        if re.search(r'[؀-ۿ]', text):
            raise ValueError(f'{key}: translation contains Arabic script.')

    # --- build -------------------------------------------------------------
    surahs = []
    for number, meta in sorted(metadata.items()):
        surahs.append({
            'number': number,
            'name_arabic': meta['name_arabic'],
            # Kept as the English meaning, which is what this field held before.
            'name_simple': meta['name_english'],
            'name_transliterated': meta['name_transliterated'],
            'revelation_place': meta['revelation_place'],
            'verse_count': meta['verse_count'],
            'bismillah': basmalas.get(number),
            'ayahs': [
                {
                    'verse_number': verse,
                    'text': arabic[(number, verse)],
                    'translation': translation[(number, verse)],
                }
                for verse in range(1, meta['verse_count'] + 1)
            ],
        })

    total_ayahs = sum(len(s['ayahs']) for s in surahs)
    if total_ayahs != EXPECTED_AYAHS:
        raise ValueError(f'Assembled {total_ayahs} ayahs, expected {EXPECTED_AYAHS}.')

    payload = {
        'attribution': attribution,
        'sources': {
            'arabic': {
                'name': 'Tanzil Project',
                'edition': 'Uthmani',
                'url': 'https://tanzil.net',
                'download': ARABIC_URL,
                'terms': (
                    'Permission is granted to copy and distribute verbatim copies of '
                    'the Quran text provided here, but changing the text is not '
                    'allowed. The text can be used in any website or application, '
                    'provided that its source (Tanzil Project) is clearly indicated, '
                    'and a link is made to tanzil.net to enable users to keep track '
                    'of changes.'
                ),
            },
            'metadata': {
                'name': 'Tanzil Project Quran metadata',
                'url': METADATA_URL,
                'licence': 'Creative Commons Attribution 3.0',
            },
            'cross_check_only_not_stored': {
                'name': 'Quran Foundation chapters endpoint',
                'url': QF_CHAPTERS_URL,
                'note': (
                    'Used at build time to verify per-surah ayah counts against an '
                    'independent source. No content from it is stored.'
                ),
            },
        },
        'translation': {
            'name': 'Yusuf Ali',
            'translator': 'Abdullah Yusuf Ali',
            'identifier': 'en.yusufali',
            'language': 'English',
            'last_update': 'May 10, 2013',
            'source': 'Tanzil.net',
        },
        'surahs': surahs,
    }

    out = ASSETS / 'quran_reader_data.json'
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8')

    manifest = {
        'arabic_source': 'Tanzil Project, Uthmani',
        'arabic_download_url': ARABIC_URL,
        'metadata_source': METADATA_URL,
        'translation_source': TRANSLATION_URL,
        'count_cross_check_url': QF_CHAPTERS_URL,
        'surah_count': len(surahs),
        'ayah_count': total_ayahs,
        'chapter_counts': {str(n): observed[n] for n in sorted(observed)},
        'arabic_character_count': sum(
            len(a['text']) for s in surahs for a in s['ayahs']
        ),
        'basmala_count': len(basmalas),
        'notes': (
            'Detects drift between runs. Per-surah counts are verified at build '
            'time against both the Tanzil metadata and the Quran Foundation '
            'chapters endpoint. Nothing from the latter is stored.'
        ),
    }
    (ASSETS / 'quran_import_manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8'
    )

    distinct = {}
    for number, text in basmalas.items():
        distinct.setdefault(text, []).append(number)

    print()
    print(f'  surahs               {len(surahs)}')
    print(f'  ayahs                {total_ayahs}')
    print(f'  basmalas separated   {len(basmalas)}')
    print(f'  distinct basmala spellings {len(distinct)}'
          f' (surahs with a shadda variant: '
          f'{sorted(n for t, ns in distinct.items() if "ّ" in t[:3] for n in ns)})')
    print(f'  arabic characters    {manifest["arabic_character_count"]}')
    print(f'  written              {out.relative_to(ROOT)} '
          f'({out.stat().st_size} bytes)')


if __name__ == '__main__':
    main()
