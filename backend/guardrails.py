"""Server-side guardrails for the study assistant.

CLAUDE.md requires the assistant to detect ruling questions and redirect them,
and to answer only from retrieved sources. The system prompt asks the model for
both, but a prompt is not an enforcement mechanism: it fails open, it varies
between calls, and it cannot be tested without spending a model call. These
checks run in our own process instead, so they are deterministic, free, and
testable.

The prompt rules stay in place. These are a second layer, not a replacement.

Bias: over-refusing is cheap and under-refusing is not. A study question wrongly
sent to a scholar costs the user one rephrase; a ruling wrongly answered is the
exact failure the brief forbids. Where the two trade off, this module refuses.
"""

import re

# Retrieval scores below this are treated as "nothing relevant found". Measured
# on all-mpnet-base-v2 over the bundled corpus: on-topic questions score
# 0.49-0.71 at rank 1, while off-topic questions (car repair, football, k8s)
# top out at 0.29. 0.35 sits in that gap with margin either side.
MIN_RELEVANCE_SCORE = 0.35

RULING_REDIRECT_MESSAGE = (
    'This is a question about religious rulings, which this study tool does not '
    'answer. Please ask a qualified scholar or your local imam. If it helps, I '
    'can show you what verses mention a topic, without ruling on it.'
)

NO_SOURCE_MESSAGE = 'The verses I have do not answer this question.'

# Vocabulary that makes a question a ruling question regardless of how it is
# framed. These words have no non-ruling reading in this context.
_RULING_TERMS = re.compile(
    r'\b('
    r'haram|haraam|halal|halaal'
    r'|permissible|impermissible|permitted|forbidden|prohibited|unlawful|lawful'
    r'|makruh|makrooh|mustahab|mustahabb|wajib|waajib|fard|fardh|farz'
    r'|fatwa|fatwas|fatwaa'
    r'|sinful|a\s+sin|any\s+sin'
    r'|obligatory|compulsory|mandatory'
    r'|nullify|nullifies|nullified|invalidate|invalidates|invalidated'
    r'|(?:prayer|prayers|salah|salat|namaz|fast|fasting|wudu|ablution|ghusl)\s+'
    r'(?:is\s+|still\s+)*(?:valid|invalid|count|counts|accepted)'
    r'|valid\s+(?:prayer|prayers|salah|salat|namaz|fast|fasting|wudu|ablution|ghusl)'
    r')\b',
    re.IGNORECASE,
)

# Asking what the religion or its law says is a ruling frame, even when the
# wording is general. Asking what *the Quran* says is not: thematic search over
# the text is an allowed capability, so "the Quran" is deliberately absent here.
_RELIGION_FRAME = re.compile(
    r'\bwhat\s+(?:does|do)\s+'
    r'(?:islam|islaam|sharia|shariah|shari\'ah|islamic\s+law|the\s+scholars?|'
    r'the\s+madhhab|my\s+religion)\s+'
    r'(?:say|says|state|states|rule|rules|teach|teaches|think|hold)\b'
    r'|\b(?:islamic|sharia|shariah)\s+'
    r'(?:ruling|rulings|law|position|stance|verdict|judgement|judgment)\b'
    r'|\b(?:allowed|permitted|banned|forbidden|okay|ok)\s+in\s+islam\b'
    r'|\bin\s+islam,?\s+(?:can|may|should|must)\s+(?:i|we|you|a|one)\b',
    re.IGNORECASE,
)

# "Can I ...", "must we ...": a request for a decision about the asker's own
# conduct rather than a request to understand the text.
_PERSONAL_MODAL = re.compile(
    r'\b(?:can|could|may|should|must|shall)\s+(?:i|we)\b'
    r'|\bdo\s+(?:i|we)\s+(?:have\s+to|need\s+to)\b'
    r'|\bam\s+i\s+(?:allowed|required|obliged|obligated|supposed)\b'
    r'|\bis\s+it\s+(?:ok|okay|fine|wrong|acceptable|alright)\s+(?:to|for|if)\b',
    re.IGNORECASE,
)

# Acts of worship and personal or family matters. On their own these are fine to
# study; combined with a personal modal above, the question is asking for a
# ruling on the asker's own practice.
_PRACTICE_TOPICS = re.compile(
    r'\b('
    r'pray|prays|prayed|praying|prayer|prayers|salah|salat|namaz'
    r'|wudu|wudhu|ablution|ghusl|tayammum'
    r'|fast|fasts|fasted|fasting|sawm|ramadan|ramadhan|iftar|suhoor|sehri'
    r'|zakat|zakah|khums'
    r'|hajj|umrah|ihram|tawaf'
    r'|marry|marrying|marries|marriage|nikah|wedding'
    r'|divorce|talaq|mahr|dowry|inheritance|custody|adopt|adoption'
    r'|alcohol|wine|beer|drink|pork|swine|gambling|lottery|riba|interest'
    r'|hijab|niqab|veil|awrah|beard'
    r'|music|dancing|tattoo|tattoos|smoking|vaping'
    r'|rakah|rakat|rakaat|rakah|adhan|azan|janazah|funeral|burial'
    r'|baptize|baptise|baptism|circumcision|aqiqah'
    r')\b',
    re.IGNORECASE,
)

# "What is the proper way to ...", "how do I perform ...": asking to be taught
# the correct performance of a rite is a question about validity, which is a
# ruling. Distinct from asking what the text says about a rite.
_PRACTICE_HOWTO = re.compile(
    r'\b(?:the\s+)?(?:proper|correct|right|prescribed|approved|acceptable)\s+'
    r'(?:way|ways|method|manner|procedure|steps|order)\s+(?:to|of|for)\b'
    r'|\bhow\s+(?:do|does|should|can|must)\s+(?:i|we|one|a\s+muslim)\s+'
    r'(?:perform|do|make|offer|observe|complete|pray|fast|give|carry\s+out)\b'
    r'|\bhow\s+many\s+(?:rakah|rakat|rakaat|times|days)\b'
    r'|\bwhat\s+are\s+the\s+(?:conditions|requirements|rules|steps|pillars)\s+(?:for|of)\b',
    re.IGNORECASE,
)

# Markers that a question is pitched at the religion or its practice rather than
# at the text. "The Quran" is deliberately absent, as in _RELIGION_FRAME.
_ISLAM_MARKER = re.compile(
    r'\b(?:in\s+islam|islam|islamic|muslim|muslims|sharia|shariah|sunnah|hadith)\b',
    re.IGNORECASE,
)

# Verse references such as "2:255". Bounded to three digits per side because the
# corpus has 114 surahs and at most 286 verses in one surah.
_CITATION = re.compile(r'\b(\d{1,3}):(\d{1,3})\b')


def is_ruling_question(question: str) -> bool:
    """True when the question asks for a religious ruling rather than for study.

    Four independent triggers, any of which is enough:
    - ruling vocabulary, e.g. "is music haram"
    - a religion-or-law frame, e.g. "what does Islam say about music"
    - a personal modal about an act of worship or a family matter, e.g.
      "can I pray without wudu"
    - a how-to-perform framing aimed at the religion or a rite, e.g. "what is
      the proper way to baptize an infant in Islam"

    The last two triggers are conjunctions on purpose. "What is the best way to
    understand this verse" is a how-to framing with no rite attached and stays
    allowed; "can you explain 2:255" is a modal with no rite and stays allowed.

    A question about what the Quran says on a topic is not a ruling question and
    is left alone, which keeps thematic search working.
    """
    text = (question or '').strip()
    if not text:
        return False
    if _RULING_TERMS.search(text):
        return True
    if _RELIGION_FRAME.search(text):
        return True
    if _PERSONAL_MODAL.search(text) and _PRACTICE_TOPICS.search(text):
        return True
    return bool(
        _PRACTICE_HOWTO.search(text)
        and (_ISLAM_MARKER.search(text) or _PRACTICE_TOPICS.search(text))
    )


def extract_citations(text: str) -> list[str]:
    """Every surah:verse reference in `text`, in order, without duplicates."""
    seen: list[str] = []
    for surah, verse in _CITATION.findall(text or ''):
        reference = f'{int(surah)}:{int(verse)}'
        if reference not in seen:
            seen.append(reference)
    return seen


def verified_citations(answer: str, references: list[str]) -> list[str]:
    """Citations in `answer` that were actually among the retrieved `references`.

    A citation the retrieval never supplied cannot have come from the provided
    context, so it is dropped rather than shown. This is what stops a fluent
    answer from carrying a reference the model produced from memory.
    """
    allowed = set(references or [])
    return [
        reference for reference in extract_citations(answer)
        if reference in allowed
    ]


def relevant_chunks(chunks: list[dict], min_score: float = MIN_RELEVANCE_SCORE) -> list[dict]:
    """The retrieved chunks strong enough to be treated as a source."""
    return [
        chunk for chunk in (chunks or [])
        if float(chunk.get('score', 0.0)) >= float(min_score)
    ]
