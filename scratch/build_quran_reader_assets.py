import json
import os
import sqlite3
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets'
ASSETS.mkdir(exist_ok=True)
(FONTS := ASSETS / 'fonts').mkdir(exist_ok=True)

font_url = 'https://raw.githubusercontent.com/aliftype/amiri/master/fonts/Amiri-Regular.ttf'
font_path = FONTS / 'AmiriQuran-Regular.ttf'
urllib.request.urlretrieve(font_url, font_path)

conn = sqlite3.connect(ASSETS / 'quran.sqlite')
conn.row_factory = sqlite3.Row

surahs = []
for row in conn.execute(
    'SELECT surah_number, name_arabic, name_simple, revelation_place, verse_count FROM surahs ORDER BY surah_number'
):
    surah_number = row['surah_number']
    ayahs = [
        {'verse_number': item['verse_number'], 'text': item['arabic_text']}
        for item in conn.execute(
            'SELECT verse_number, arabic_text FROM ayahs WHERE surah_number = ? ORDER BY verse_number',
            (surah_number,),
        ).fetchall()
    ]
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

with open(ASSETS / 'quran_reader_data.json', 'w', encoding='utf-8') as f:
    json.dump({'surahs': surahs}, f, ensure_ascii=False, indent=2)

assert len(surahs) == 114, f'Expected 114 surahs, found {len(surahs)}'
assert sum(len(surah['ayahs']) for surah in surahs) == 6236, (
    f'Expected 6236 ayahs total, found {sum(len(surah["ayahs"]) for surah in surahs)}'
)

print(f'Font: {font_path} ({font_path.stat().st_size} bytes)')
print(f'Surah count: {len(surahs)}')
print(f'Ayah total: {sum(len(surah["ayahs"]) for surah in surahs)}')
print(f'First surah: {surahs[0]["number"]} - {surahs[0]["name_simple"]}')
print(f'Last surah: {surahs[-1]["number"]} - {surahs[-1]["name_simple"]}')
