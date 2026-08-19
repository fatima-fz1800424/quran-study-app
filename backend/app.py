import os

from dotenv import load_dotenv
from fastapi import FastAPI

load_dotenv()

app = FastAPI(title='Quran Study App Backend')


@app.get('/health')
def health() -> dict[str, str]:
    _ = os.getenv('ANTHROPIC_API_KEY')
    return {'status': 'ok'}
