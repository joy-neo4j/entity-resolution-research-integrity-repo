#!/usr/bin/env bash
set -euo pipefail

# One-command Linux Docker runner for the full Aura pipeline.
# Usage:
#   bash scripts/run_full_pipeline_linux_docker.sh
#   bash scripts/run_full_pipeline_linux_docker.sh --gds-target auradb-ga --data-dir data --reset
# Optional env vars:
#   PY_IMAGE=python:3.12-slim
#   GDS_VERSION=1.14

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY_IMAGE="${PY_IMAGE:-python:3.12-slim}"
GDS_VERSION="${GDS_VERSION:-}"

if [[ $# -eq 0 ]]; then
  set -- --gds-target auradb-ga --data-dir data --reset
fi

cd "$REPO_ROOT"

echo "Running full pipeline in Linux container: $PY_IMAGE"
if [[ -n "$GDS_VERSION" ]]; then
  echo "Pinning graphdatascience==$GDS_VERSION"
fi

tar \
  --exclude=.git \
  --exclude=.venv \
  --exclude=.venv312 \
  --exclude=__pycache__ \
  -cf - . \
| MSYS_NO_PATHCONV=1 docker run --rm -i "$PY_IMAGE" bash -lc "
  set -e
  mkdir -p /work
  tar -C /work -xf -
  cd /work
  python -m pip install --no-cache-dir -r requirements.txt
  if [ -n '$GDS_VERSION' ]; then
    python -m pip install --no-cache-dir graphdatascience==$GDS_VERSION
  fi
  python scripts/run_full_aura_pipeline.py $*
"
