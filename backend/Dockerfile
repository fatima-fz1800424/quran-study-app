# Backend image for the Quran Study App.
#
# Build from inside `backend/`, so the build context is just this directory
# rather than the whole Flutter project:
#
#   docker build -t quran-backend backend/
#
# The retriever resolves its paths from `retrieval.py`'s own location
# (`ROOT = Path(__file__).resolve().parent.parent`), so the code has to sit one
# directory below the root it expects. Hence /app/backend, not /app.

# Pinned to the same minor as the development venv (3.13.7) so a bug that
# reproduces locally reproduces here. If the PyTorch CPU index has no cp313
# wheel on your build date, rebuild with `--build-arg PYTHON_TAG=3.12-slim`;
# nothing in this codebase needs 3.13.
ARG PYTHON_TAG=3.13-slim
FROM python:${PYTHON_TAG}

# Chosen once, used by both build-time bake steps and the app at runtime, so
# the embeddings baked into the image cannot disagree with the model that reads
# them. Overridable: `--build-arg RETRIEVAL_MODEL=sentence-transformers/all-MiniLM-L6-v2`
# builds the small-model variant instead.
ARG RETRIEVAL_MODEL=sentence-transformers/all-mpnet-base-v2
ENV RETRIEVAL_MODEL=${RETRIEVAL_MODEL}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HF_HUB_DISABLE_TELEMETRY=1

WORKDIR /app/backend

# ---------------------------------------------------------------------------
# Layer 1: dependencies. Only requirements.txt is copied, so this layer is
# reused for every build where the pins have not changed - which is nearly
# every build. Copying the app code first instead would throw away a
# multi-minute torch install on every one-line edit to app.py.
# ---------------------------------------------------------------------------
COPY requirements.txt ./

# torch comes first, and from PyTorch's CPU index, because it is not in
# requirements.txt at all - it arrives transitively through
# sentence-transformers, and the default PyPI wheel for Linux bundles the CUDA
# runtime. That is roughly 2GB of GPU libraries for a container that will only
# ever run on a shared CPU. Installing the CPU build first means the
# sentence-transformers install below sees the requirement already satisfied
# and leaves it alone.
#
# Deliberately a range, not an exact pin: this was written on a machine with no
# container runtime, so the resolved version could not be verified by building.
# After your first successful build, run `docker run --rm quran-backend pip show
# torch` and pin the version you actually got.
RUN pip install --index-url https://download.pytorch.org/whl/cpu "torch>=2.5,<3" \
 && pip install -r requirements.txt

# ---------------------------------------------------------------------------
# Layer 2: model weights. No application code is involved, so editing the app
# never re-downloads ~420MB of weights. Baked in rather than fetched on first
# run: a container filesystem is ephemeral, so a first-run download happens
# again after every restart, and on a free tier that sleeps when idle that
# means every cold start pays it.
# ---------------------------------------------------------------------------
RUN python -c "\
import os;\
from sentence_transformers import SentenceTransformer;\
SentenceTransformer(os.environ['RETRIEVAL_MODEL'], cache_folder='/app/backend/.retrieval_cache/hf_model')"

# ---------------------------------------------------------------------------
# Layer 3: corpus embeddings. These depend on corpus.json and on retrieval.py,
# and on nothing else, so they are built from just those two files. Editing
# app.py does not re-embed 6236 verses; editing the corpus correctly does,
# because `_load_or_build_embeddings` keys its cache on a hash of the corpus
# text plus the model name.
# ---------------------------------------------------------------------------
COPY corpus.json retrieval.py ./
RUN python -c "\
import os;\
from retrieval import retriever;\
retriever.initialize(model_name=os.environ['RETRIEVAL_MODEL'])"

# ---------------------------------------------------------------------------
# Layer 4: application code. Last, because it changes most often.
# ---------------------------------------------------------------------------
COPY . ./

# Non-root. The baked cache is read-only in normal operation; ownership is
# handed over anyway so that a corpus change at runtime can still write a new
# embedding file instead of crashing on a permission error.
RUN useradd --create-home --uid 10001 appuser \
 && chown -R appuser:appuser /app
USER appuser

# Documentation only - the real port comes from $PORT at runtime.
EXPOSE 8123

# curl and wget are not in the slim image, so the check uses the interpreter
# that is definitely present. $PORT is read inside the container, so the check
# follows whatever the platform assigned.
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD ["python", "-c", "import os,urllib.request,sys;\
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+os.getenv('PORT','8123')+'/health',timeout=4).status==200 else 1)"]

# Bound to $PORT, not a hardcoded port: Railway, Render and Fly all assign one
# and expect the process to listen on it. Falls back to 8123 for local runs,
# which is what the Flutter client defaults to.
#
# `sh -c` because ${PORT} needs a shell to expand, and `exec` so that uvicorn
# replaces the shell as PID 1 and receives SIGTERM directly - without it the
# shell swallows the signal and the platform waits out its grace period before
# killing the container on every deploy.
CMD ["sh", "-c", "exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8123}"]
