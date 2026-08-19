import json
import re
import sqlite3
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets'
ASSETS.mkdir(exist_ok=True)
(FONTS := ASSETS / 'fonts').mkdir(exist_ok=True)

font_url = 'https://raw.githubusercontent.com/aliftype/amiri/master/fonts/Amiri-Regular.ttf'
font_path = FONTS / 'AmiriQuran-Regular.ttf'
urllib.request.urlretrieve(font_url, font_path)

translation_url = 'https://tanzil.net/trans/en.yusufali?type=xml'
translation_req = urllib.request.Request(
    translation_url,
    headers={'User-Agent': 'Mozilla/5.0'},
)
with urllib.request.urlopen(translation_req, timeout=30) as response:
    translation_xml = response.read().decode('utf-8', 'replace')

comment_match = re.search(r'<!--(.*?)-->', translation_xml, flags=re.DOTALL)
if comment_match is None:
    raise ValueError('Missing Tanzil attribution header in translation XML.')
attribution_notice = comment_match.group(1).strip()
translation_xml = translation_xml.replace(comment_match.group(0), '', 1)

translation_root = ET.fromstring(translation_xml)
translation_map = {}
for sura in translation_root.findall('sura'):
    surah_number = int(sura.get('index'))
    for aya in sura.findall('aya'):
        verse_number = int(aya.get('index'))
        text = aya.get('text')
        if text is None:
            raise ValueError(f'Missing translation text for surah {surah_number}, ayah {verse_number}')
        translation_map[(surah_number, verse_number)] = text

assert len(translation_map) == 6236, (
    f'Expected 6236 translated ayahs, found {len(translation_map)}'
)
assert all(text.strip() for text in translation_map.values()), 'Translation text contains empty entries.'
assert not any(re.search(r'[\u0600-\u06FF]', text) for text in translation_map.values()), (
    'Translation text contains Arabic script.'
)

conn = sqlite3.connect(ASSETS / 'quran.sqlite')
conn.row_factory = sqlite3.Row

surahs = []
for row in conn.execute(
    'SELECT surah_number, name_arabic, name_simple, revelation_place, verse_count FROM surahs ORDER BY surah_number'
):
    surah_number = row['surah_number']
    ayahs = []
    for item in conn.execute(
        'SELECT verse_number, arabic_text FROM ayahs WHERE surah_number = ? ORDER BY verse_number',
        (surah_number,),
    ).fetchall():
        verse_number = item['verse_number']
        arabic_text = item['arabic_text']
        translation_text = translation_map.get((surah_number, verse_number))
        if translation_text is None:
            raise ValueError(
                f'Missing translation for surah {surah_number}, ayah {verse_number}.'
            )
        ayahs.append(
            {
                'verse_number': verse_number,
                'text': arabic_text,
                'translation': translation_text,
            }
        )
    surahs.append(
        {
            'number': surah_number,
            'name_arabic': row['name_arabic'],
            'name_simple': row['name_simple'],
            'revelation_place': row['revelation_place'],
            'verse_count': row['verse_count'],
            'ayahs': ayahs,
        }
    )

conn.close()

assert len(surahs) == 114, f'Expected 114 surahs, found {len(surahs)}'
assert sum(len(surah['ayahs']) for surah in surahs) == 6236, (
    f'Expected 6236 ayahs total, found {sum(len(surah["ayahs"]) for surah in surahs)}'
)

payload = {
    'attribution': attribution_notice,
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

with open(ASSETS / 'quran_reader_data.json', 'w', encoding='utf-8') as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)

print(f'Font: {font_path} ({font_path.stat().st_size} bytes)')
print(f'Surah count: {len(surahs)}')
print(f'Ayah total: {sum(len(surah["ayahs"]) for surah in surahs)}')
print(f'Translation rows: {len(translation_map)}')
print(f'Translation source: {payload["translation"]["source"]} / {payload["translation"]["translator"]}')
print(f'First surah: {surahs[0]["number"]} - {surahs[0]["name_simple"]}')
print(f'Last surah: {surahs[-1]["number"]} - {surahs[-1]["name_simple"]}')
