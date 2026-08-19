# Sources and Attributions

## Quran corpus

- Source: Quran.com API v4
- Independent chapter-count endpoint: https://api.quran.com/api/v4/chapters?language=en
- Uthmani Arabic text endpoint: https://api.quran.com/api/v4/quran/verses/uthmani?chapter_number={chapter_number}
- Edition identifier: quran-uthmani
- Edition name: Uthmani
- Fetched on: 2026-08-19

## English translation

- Source: Tanzil Project
- Translation: Yusuf Ali
- Translator: Abdullah Yusuf Ali
- Language: English
- ID: en.yusufali
- Last Update: May 10, 2013
- Source URL: https://tanzil.net

Required copyright notice reproduced from the Tanzil XML header:

```text
# --------------------------------------------------------------------
#
#  Quran Translation
#  Name: Yusuf Ali
#  Translator: Abdullah Yusuf Ali
#  Language: English
#  ID: en.yusufali
#  Last Update: May 10, 2013
#  Source: Tanzil.net
#
# --------------------------------------------------------------------
```

This attribution is retained in the generated JSON payload under the top-level `attribution` field and is shown in-app as part of the UI attribution for the reader.

## Third parties that receive user data

Everything below is confined to the AI assistant tab. Reading, search,
bookmarks and settings send nothing anywhere.

### Google Gemini - questions typed or dictated

Questions sent to the assistant, together with the retrieved verse
translations used as context, are sent to the Gemini API through our own
backend. The API key stays on the backend and never reaches the client.

### Browser speech service - audio of the user's voice

Dictation uses `speech_to_text`, which on the web is a wrapper over the
browser's Web Speech API. In Chrome that means **the audio of what the user
says is sent off the device** to a speech service operated by the browser
vendor, not to us. This is the most sensitive data flow in the app, and it is
the only one where something other than typed text leaves the machine.

Consequences we accept and disclose:

- The app shows a notice explaining this and requires the user to accept it
  **before** the microphone is ever opened, not after the first recording. See
  `docs/DECISIONS.md`.
- The app itself neither records nor stores audio, and keeps no transcript
  beyond the question the user chooses to send.
- Dictation therefore requires a network connection. That is consistent with
  where the offline line already sits: CLAUDE.md rule 5 exempts the assistant,
  which needs connectivity regardless. Voice lives entirely inside the
  assistant tab, so the offline-first guarantee for reading is unaffected.
- Where the platform reports no speech support, the control is hidden rather
  than shown failing, so no audio is captured on platforms we have not
  verified.

Reading answers aloud uses `flutter_tts`, which on the web uses the browser's
own voices. It is given the assistant's English answer only. Quranic Arabic is
never passed to a speech engine: a general-purpose English voice mispronounces
it, and the rule against producing Quranic text from anything but the verified
corpus applies to audio as much as to text.
