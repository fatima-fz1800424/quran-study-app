# Sources and Attributions

## Quran corpus

### Arabic text - Tanzil Project

- Source: Tanzil Project, Uthmani edition
- Download: `https://tanzil.net/pub/download/index.php?quranType=uthmani&outType=txt-2&marks=true&sajdah=true&rub=true&tatweel=true&agree=true`
- Re-imported on: 2026-08-20 (previously Quran.com API v4 - see below)
- Built by: `tool/build_quran_assets.py`

Stated terms, quoted from https://tanzil.net/download/:

> "Permission is granted to copy and distribute verbatim copies of the Quran
> text provided here, but changing the text is not allowed. The text can be used
> in any website or application, provided that its source (Tanzil Project) is
> clearly indicated, and a link is made to tanzil.net to enable users to keep
> track of changes."

The app satisfies this: the text is bundled verbatim, Tanzil is named in the
reader's attribution, and a link to tanzil.net is shown in the reader settings.

### Surah metadata - Tanzil Project

- Source: `https://tanzil.net/res/text/metadata/quran-data.js`
- Licence, quoted from the file header: `Copyright (C) 2008-2009 Tanzil.info` /
  `License: Creative Commons Attribution 3.0`
- Supplies surah names (Arabic, transliterated, English), ayah counts and
  revelation place.

### Quran.com / Quran Foundation - build-time cross-check only, nothing stored

- Endpoint: https://api.quran.com/api/v4/chapters?language=en
- Used by the importer to verify per-surah ayah counts against an independent
  source. **No content from it is written to disk.**

The Arabic text previously came from the Quran.com API v4 (`quran-uthmani`
edition, fetched 2026-08-19) and was bundled permanently. That was changed
because it conflicts with the [Quran Foundation Developer
Terms](https://api-docs.quran.foundation/legal/developer-terms/), quoted:

> "Cache or store QF Content longer than **1 week**, except where (a) QF has
> expressly permitted longer storage, or (b) the QF Content is available through
> the Content Sync APIs"

> "QF Content is **not resold, sublicensed, or redistributed** except as
> integral to the end-user experience of the Application."

An offline-first app bundling their text in a public repository cannot satisfy a
one-week storage limit. Tanzil's terms permit exactly what this app does, so the
text was re-imported from there. The two editions were compared ayah by ayah
first: **the Arabic is character-identical**, so nothing about the displayed text
changed. See `docs/DECISIONS.md`.

`assets/quran.sqlite` was deleted in the same change. It held a second copy of
the QF-sourced Arabic, was bundled into the web build, and no runtime code read
it.

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
