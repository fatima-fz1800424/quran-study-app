# Build Brief - Quran Study App with AI Assistant

Read CLAUDE.md first. Its rules override anything below if they conflict.

## Core features

1. **Surah list** - number, Arabic name, English name, revelation place, ayah count; search by name or number
2. **Reader view** - Uthmani Arabic with correct RTL rendering, adjustable font size, ayah-by-ayah or continuous mode, optional translation beneath each ayah
3. **Audio recitation** - per-ayah playback, reciter selection, auto-scroll to playing ayah, background audio, download-for-offline
4. **Bookmarks and last-read** - persisted locally, resume where the user left off
5. **Navigation** - Juz / Hizb browsing and go-to-ayah jump
6. **Settings** - theme, Arabic font, translation, reciter

## AI study assistant

Scope: a study aid, not a religious authority.

### Architecture
- FastAPI backend proxy holding the LLM API key. Never in the client.
- Retrieval-augmented: answers come only from a bundled corpus of attributed sources, retrieved and passed as context. Never from model memory.
- Corpus: classical tafsir with clear licensing (e.g. Ibn Kathir, al-Jalalayn abridged English via Quran.com tafsir endpoints) plus bundled translations. Store every chunk with source name and surah:ayah.
- Embed the corpus; store vectors locally (sqlite-vec) or server-side.

### Allowed capabilities
- What is this ayah about - return retrieved tafsir, source named inline
- Explain a word or root in an ayah, citing the translation
- Thematic search returning references, not paraphrase
- Historical context where the retrieved sources state it
- Summarise a surah's themes, citing which tafsir the summary came from

### Hard constraints - in the system prompt AND as UI guardrails
- Never issue fatwas or rulings on halal/haram, worship validity, or personal and family matters. Detect and redirect to a qualified scholar or local imam.
- Never generate Quranic Arabic. Quote only by rendering from the verified local database.
- Every substantive answer displays its source. No relevant retrieval means the assistant says so rather than guessing.
- Persistent, non-dismissible note in the assistant UI: this is a study tool drawing on classical tafsir, not a substitute for a qualified scholar.
- Log nothing about user questions beyond what the request requires.

## Stages - pause after each for review

1. Scaffold, data model, verified Quran import + verification script
2. Surah list and reader view with Arabic rendering
3. Audio playback and offline downloads
4. Bookmarks, last-read, settings
5. AI assistant: backend proxy, corpus ingest, retrieval, guardrails, UI
6. Tests, polish, README with sources and licences

Start with Stage 1. Ask before assuming anything about scope.
