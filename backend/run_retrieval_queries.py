import json
from fastapi.testclient import TestClient
from app import app

queries = [
    'patience in hardship',
    'what does the Quran say about orphans',
    'charity and giving to the poor',
    'the story of Moses and Pharaoh',
    'how should I treat my parents',
]

client = TestClient(app)
results = {}
for q in queries:
    r = client.get('/search', params={'q': q, 'k': 5})
    results[q] = r.json()

with open('backend/retrieval_results.json', 'w', encoding='utf-8') as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

print(json.dumps(results, ensure_ascii=False, indent=2))
