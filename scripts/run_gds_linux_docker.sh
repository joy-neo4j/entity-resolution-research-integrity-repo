#!/usr/bin/env bash
set -euo pipefail

# One-command Linux Docker workaround for Windows TLS/OAuth and runtime drift.
# Usage:
#   bash scripts/run_gds_linux_docker.sh
#   bash scripts/run_gds_linux_docker.sh --target auradb-ga --file cypher/04_gds_workflows.cypher
# Optional env vars:
#   PY_IMAGE=python:3.12-slim
#   GDS_VERSION=1.14

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY_IMAGE="${PY_IMAGE:-python:3.12-slim}"
GDS_VERSION="${GDS_VERSION:-}"

if [[ $# -eq 0 ]]; then
  set -- --target auradb-ga --file cypher/04_gds_workflows.cypher
fi

cd "$REPO_ROOT"

echo "Running in Linux container: $PY_IMAGE"
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
  python scripts/run_gds.py $*
"
