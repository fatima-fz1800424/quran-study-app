"""Guardrail tests for the /ask endpoint.

The Gemini call is replaced in every test, so these need no API key and no
network. They cover what this codebase controls - refusal decisions, the
relevance floor, citation checking, and prompt construction - and deliberately
do not assert anything about what Gemini would say.

Fixture verse text below is placeholder prose, not scripture. Nothing here
reproduces Quranic Arabic or a real translation from model memory.
"""

import sys
from pathlib import Path

import pytest
from fastapi import HTTPException

BACKEND_DIR = Path(__file__).resolve().parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import app as app_module  # noqa: E402
import guardrails  # noqa: E402

RETRIEVED = [
    {'reference': '2:153', 'translation_text': 'Placeholder verse text A.', 'score': 0.62},
    {'reference': '3:200', 'translation_text': 'Placeholder verse text B.', 'score': 0.51},
]


class _FakeRetriever:
    """Stands in for the embedding retriever so no model has to load."""

    def __init__(self, chunks):
        self.chunks = chunks
        self.calls = []

    def search(self, query, **kwargs):
        self.calls.append(query)
        return [dict(chunk) for chunk in self.chunks]


@pytest.fixture
def fake_retriever(monkeypatch):
    fake = _FakeRetriever(RETRIEVED)
    monkeypatch.setattr(app_module, 'retriever', fake)
    return fake


@pytest.fixture
def gemini(monkeypatch):
    """Replace the model call; record prompts and serve a scripted reply."""

    class Recorder:
        def __init__(self):
            self.prompts = []
            self.reply = 'Patience is described in 2:153.'

        def __call__(self, prompt):
            self.prompts.append(prompt)
            return self.reply

    recorder = Recorder()
    monkeypatch.setattr(app_module, '_call_gemini', recorder)
    return recorder


@pytest.fixture
def model_must_not_be_called(monkeypatch):
    def explode(prompt):
        raise AssertionError('the model was called for a question that must be refused')

    monkeypatch.setattr(app_module, '_call_gemini', explode)


# --------------------------------------------------------------------------
# Ruling questions
# --------------------------------------------------------------------------

FIQH_QUESTIONS = [
    'is music haram',
    'can I pray without wudu',
    'should I fast while travelling',
]


@pytest.mark.parametrize('question', FIQH_QUESTIONS)
def test_fiqh_questions_are_redirected(question, fake_retriever, model_must_not_be_called):
    result = app_module.ask({'question': question})

    assert result['status'] == 'refused_ruling'
    assert result['answer'] == guardrails.RULING_REDIRECT_MESSAGE
    assert 'scholar' in result['answer'] or 'imam' in result['answer']
    assert result['citations'] == []
    # The refusal is reached before retrieval, so nothing was even looked up.
    assert fake_retriever.calls == []


def test_ruling_rephrased_as_a_general_question_still_redirects(
    fake_retriever, model_must_not_be_called
):
    result = app_module.ask({'question': 'what does Islam say about music'})

    assert result['status'] == 'refused_ruling'
    assert result['answer'] == guardrails.RULING_REDIRECT_MESSAGE


@pytest.mark.parametrize(
    'question',
    [
        'is it permissible to listen to music',
        'do I have to fast if I am ill',
        'what is the Islamic ruling on interest',
        'is my prayer still valid if I forget a rakah',
        'is it allowed in Islam to adopt a child',
        'am I required to give zakat on savings',
    ],
)
def test_other_ruling_phrasings_are_redirected(
    question, fake_retriever, model_must_not_be_called
):
    assert app_module.ask({'question': question})['status'] == 'refused_ruling'


@pytest.mark.parametrize(
    'question',
    [
        'what does the Quran say about patience',
        'what does the Quran say about fasting',
        'what is 2:255 about',
        'explain the story of Musa and Khidr',
        'which verses mention orphans',
        'summarise the themes of surah 16',
        'can you explain the context of 9:5',
    ],
)
def test_study_questions_are_not_refused(question, fake_retriever, gemini):
    """The guardrail must not swallow the app's actual purpose.

    Note the last case: "can you explain ..." is a personal modal in form but
    asks about the text, so it must still reach the model.
    """
    result = app_module.ask({'question': question})

    assert result['status'] == 'ok'
    assert len(gemini.prompts) == 1


# --------------------------------------------------------------------------
# Nothing relevant retrieved
# --------------------------------------------------------------------------

def test_declines_when_retrieval_finds_nothing_relevant(monkeypatch, model_must_not_be_called):
    weak = [
        {'reference': '18:32', 'translation_text': 'Placeholder verse text.', 'score': 0.21},
        {'reference': '7:12', 'translation_text': 'Placeholder verse text.', 'score': 0.19},
    ]
    monkeypatch.setattr(app_module, 'retriever', _FakeRetriever(weak))

    result = app_module.ask({'question': 'how do I change a car tyre'})

    assert result['status'] == 'no_source'
    assert result['answer'] == guardrails.NO_SOURCE_MESSAGE
    assert result['references'] == []
    assert result['citations'] == []


def test_declines_when_retrieval_returns_nothing_at_all(monkeypatch, model_must_not_be_called):
    monkeypatch.setattr(app_module, 'retriever', _FakeRetriever([]))

    result = app_module.ask({'question': 'what does the Quran say about quantum physics'})

    assert result['status'] == 'no_source'
    assert result['answer'] == guardrails.NO_SOURCE_MESSAGE


def test_a_single_relevant_verse_is_enough_to_answer(monkeypatch, gemini):
    mixed = [
        {'reference': '2:153', 'translation_text': 'Placeholder verse text.', 'score': 0.55},
        {'reference': '7:12', 'translation_text': 'Placeholder verse text.', 'score': 0.12},
    ]
    monkeypatch.setattr(app_module, 'retriever', _FakeRetriever(mixed))

    result = app_module.ask({'question': 'what does the Quran say about patience'})

    assert result['status'] == 'ok'
    # The weak verse is dropped before the prompt is built.
    assert result['references'] == ['2:153']
    assert '7:12' not in gemini.prompts[0]


# --------------------------------------------------------------------------
# Citations
# --------------------------------------------------------------------------

def test_an_answer_carries_verified_citations(fake_retriever, gemini):
    gemini.reply = 'Patience is described in 2:153, and endurance in 3:200.'

    result = app_module.ask({'question': 'what does the Quran say about patience'})

    assert result['status'] == 'ok'
    assert result['citations'] == ['2:153', '3:200']


def test_an_answer_without_any_citation_is_not_shown(fake_retriever, gemini):
    gemini.reply = 'Patience is a virtue and believers are encouraged to have it.'

    result = app_module.ask({'question': 'what does the Quran say about patience'})

    assert result['status'] == 'no_source'
    assert result['answer'] == guardrails.NO_SOURCE_MESSAGE


def test_citations_the_retrieval_never_supplied_are_not_trusted(fake_retriever, gemini):
    # 4:34 was not retrieved, so the model cannot have got it from the context.
    gemini.reply = 'This is addressed in 4:34.'

    result = app_module.ask({'question': 'what does the Quran say about patience'})

    assert result['status'] == 'no_source'
    assert '4:34' not in result['citations']


def test_unretrieved_citations_are_dropped_but_valid_ones_survive(fake_retriever, gemini):
    gemini.reply = 'See 2:153, and also 4:34.'

    result = app_module.ask({'question': 'what does the Quran say about patience'})

    assert result['status'] == 'ok'
    assert result['citations'] == ['2:153']


def test_every_answered_response_cites_at_least_one_verse(fake_retriever, gemini):
    """The invariant behind the individual cases above."""
    for reply in [
        'Patience is described in 2:153.',
        'See 2:153 and 3:200.',
        'No verse here addresses this.',
        'Believers should be patient.',
        'Consider 4:34 instead.',
    ]:
        gemini.reply = reply
        result = app_module.ask({'question': 'what does the Quran say about patience'})

        if result['status'] == 'ok':
            assert result['citations'], f'answered with no citation: {reply!r}'
            assert all(c in result['references'] for c in result['citations'])
        else:
            assert result['answer'] == guardrails.NO_SOURCE_MESSAGE


# --------------------------------------------------------------------------
# Prompt construction
# --------------------------------------------------------------------------

def test_prompt_contains_the_question_and_only_retrieved_verses(fake_retriever, gemini):
    app_module.ask({'question': 'what does the Quran say about patience'})
    prompt = gemini.prompts[0]

    assert 'what does the Quran say about patience' in prompt
    for chunk in RETRIEVED:
        assert chunk['reference'] in prompt
        assert chunk['translation_text'] in prompt


def test_prompt_states_the_hard_constraints(fake_retriever, gemini):
    app_module.ask({'question': 'what does the Quran say about patience'})
    prompt = gemini.prompts[0].lower()

    # The prompt layer must keep carrying the rules even though refusal is now
    # enforced in code, because the model still shapes the wording of answers.
    assert 'never issue religious rulings' in prompt
    assert 'never generate arabic' in prompt
    assert 'scholar' in prompt
    assert 'cite' in prompt


def test_empty_question_is_rejected(fake_retriever, model_must_not_be_called):
    for payload in [{'question': ''}, {'question': '   '}, {}]:
        with pytest.raises(HTTPException) as raised:
            app_module.ask(payload)
        assert raised.value.status_code == 400


# --------------------------------------------------------------------------
# Detector unit tests
# --------------------------------------------------------------------------

def test_is_ruling_question_boundaries():
    assert guardrails.is_ruling_question('is music haram')
    assert guardrails.is_ruling_question('can I pray without wudu')
    assert guardrails.is_ruling_question('should I fast while travelling')
    assert guardrails.is_ruling_question('what does Islam say about music')

    assert not guardrails.is_ruling_question('what does the Quran say about music')
    assert not guardrails.is_ruling_question('which verses mention prayer')
    assert not guardrails.is_ruling_question('')
    assert not guardrails.is_ruling_question(None)


def test_extract_citations_ignores_non_references():
    assert guardrails.extract_citations('see 2:153 and 2:153 again') == ['2:153']
    assert guardrails.extract_citations('no references here') == []
    assert guardrails.extract_citations('') == []


def test_relevance_floor_is_inclusive():
    at_floor = [{'reference': '1:1', 'score': guardrails.MIN_RELEVANCE_SCORE}]
    below = [{'reference': '1:1', 'score': guardrails.MIN_RELEVANCE_SCORE - 0.01}]

    assert len(guardrails.relevant_chunks(at_floor)) == 1
    assert guardrails.relevant_chunks(below) == []
