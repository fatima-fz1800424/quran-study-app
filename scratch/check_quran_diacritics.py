import re
import sqlite3
from pathlib import Path

DB_PATH = Path(r"C:\Users\fatim\quran_study_app\assets\quran.sqlite")
assert DB_PATH.exists(), f"Missing DB: {DB_PATH}"

pattern = re.compile(r'[\u064B-\u0652]')
conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()
rows = cur.execute("SELECT surah_number, verse_number, arabic_text FROM ayahs ORDER BY surah_number, verse_number").fetchall()
missing = []
for surah, verse, text in rows:
    if not pattern.search(text or ''):
        missing.append(f"{surah}:{verse}")

print(f"Total ayahs checked: {len(rows)}")
print(f"Missing diacritics: {len(missing)}")
print("\n".join(missing))
conn.close()
