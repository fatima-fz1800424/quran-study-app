# Quran Study App Backend

This is the FastAPI backend skeleton for the Quran Study App.

## Install

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## Environment

The app reads the Anthropic API key from the `ANTHROPIC_API_KEY` environment variable.

```bash
export ANTHROPIC_API_KEY="your_key_here"
# Windows PowerShell:
# $env:ANTHROPIC_API_KEY = "your_key_here"
```

## Run

```bash
uvicorn app:app --reload --host 127.0.0.1 --port 8000
```

## Health check

```bash
curl http://127.0.0.1:8000/health
```

Expected response:

```json
{"status": "ok"}
```
