# Entity Resolution for Research Integrity

This repository implements entity resolution and research integrity workflows with two production paths:

1. AuraDB + Aura Graph Analytics Session (`auradb-ga` via `GdsSessions`)
2. AuraDB + AuraDS (`aurads` direct GDS procedures)

## 1) Repository Layout

- `cypher/01_constraints_indexes.cypher`: constraints and indexes
- `cypher/02_sample_graph.cypher`: direct sample graph creation (no CSV)
- `cypher/03_entity_resolution_queries.cypher`: ER candidate and scoring queries
- `cypher/04_gds_workflows.cypher`: GDS workflow (WCC, FastRP+KNN, Link Prediction, Louvain, PageRank, Betweenness)
- `cypher/05_integrity_competitive_queries.cypher`: integrity and competitive intelligence queries (includes 6.3 and 7.2)
- `data/*.csv`: normalized sample dataset
- `scripts/load_data_to_auradb.py`: loads local CSVs into AuraDB using Neo4j driver
- `scripts/run_cypher_file.py`: runs any `.cypher` file on AuraDB or AuraDS
- `scripts/run_gds.py`: runs GDS with:
	- `auradb-ga`: Aura Graph Analytics Session via `graphdatascience.session.GdsSessions`
	- `aurads`: direct execution on AuraDS endpoint
- `scripts/run_full_aura_pipeline.py`: orchestrates full sequence

## 2) Prerequisites

1. Python 3.11+ installed.
2. Install dependencies:

```bash
pip install -r requirements.txt
```

Optional but recommended for reproducible testing:

```bash
py -3.12 -m venv .venv312
./.venv312/Scripts/python.exe -m pip install -r requirements.txt
```

3. Create `.env` from `.env.example`.

## 3) Configure Environment Variables

### 3.1 Required for AuraDB load/query

- `AURA_DB_URI`
- `AURA_DB_USERNAME`
- `AURA_DB_PASSWORD`
- `AURA_DB_DATABASE` (usually `neo4j`)

### 3.2 Required for AuraDS execution (`--target aurads`)

- `AURA_DS_URI`
- `AURA_DS_USERNAME`
- `AURA_DS_PASSWORD`
- `AURA_DS_DATABASE`

### 3.3 Required for Aura Graph Analytics Session (`--target auradb-ga`)

- `AURA_CLIENT_ID`
- `AURA_CLIENT_SECRET`
- `AURA_PROJECT_ID` (optional; auto-resolved from `AURA_DB_URI` when omitted)

## 4) Step-by-Step Execution (Low Level)

Run from repository root.

### Step 1: Apply schema to AuraDB

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/01_constraints_indexes.cypher
```

Expected: 9 statements complete.

### Step 2: Load local CSV data to AuraDB

```bash
python scripts/load_data_to_auradb.py --data-dir data --reset
```

Expected: load counters for each node and relationship CSV.

### Step 3: Run entity resolution queries on AuraDB

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/03_entity_resolution_queries.cypher
```

### Step 4: Run integrity and competitive intelligence queries on AuraDB

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/05_integrity_competitive_queries.cypher
```

### Step 5A: Run GDS via Aura Graph Analytics Session

```bash
python scripts/run_gds.py --target auradb-ga --file cypher/04_gds_workflows.cypher
```

Implementation detail: this path uses `GdsSessions` with Aura API credentials and creates a temporary analytics session.

If your environment hits Aura Graph Analytics TLS/OAuth session issues, use the one-command pipeline in section 5 to auto-fallback to AuraDS.

### Step 5B: Run GDS on AuraDS

```bash
python scripts/run_gds.py --target aurads --file cypher/04_gds_workflows.cypher
```

Implementation detail: this path runs Cypher directly on the AuraDS Bolt endpoint.

## 5) One-Command Pipeline

Use this after `.env` is configured.

Aura Graph Analytics Session target:

```bash
python scripts/run_full_aura_pipeline.py --gds-target auradb-ga --data-dir data --reset
```

Behavior: if Aura Graph Analytics fails with TLS/OAuth or Arrow session auth errors, the pipeline automatically switches to AuraDS and continues.

AuraDS target:

```bash
python scripts/run_full_aura_pipeline.py --gds-target aurads --data-dir data --reset
```

## 6) Local Docker Mode (Optional)

For local-only experimentation:

```bash
docker compose up -d
```

Then use `scripts/load_all.cypher` only for local Docker import (`file:///`).

## 7) Troubleshooting

1. `ProcedureNotFound` for GDS procedures:
Use `--target auradb-ga` with valid Aura API credentials or switch to AuraDS.

2. `Cannot resolve address ...databases.neo4j.io`:
DNS/network issue to the configured Aura endpoint. Validate URI and network access.

3. Aura Graph Analytics reports versionless behavior:
Expected; `gds.version()` may not be available. Session-based execution still works.

4. Warnings about `SAME_AS` or `communityId`:
These can appear before corresponding write steps create relationships/properties.

5. Link prediction training fails with `Need at least one model candidate for training`:
On very small demo graphs this is expected. The runner treats this as a non-fatal skip and continues with later GDS steps.

## 8) Compatibility Notes

- `scripts/load_all.cypher` is not Aura-compatible (`file:///` usage).
- `cypher/04_gds_workflows.cypher` uses native projection patterns to avoid `gds.graph.project.cypher` dependency.

## 9) Linux Docker Workaround (Windows TLS/OAuth)

If Windows runtime hits `SSLEOFError` / OAuth handshake issues for `api.neo4j.io`, run inside a Linux container.

From repository root in Git Bash:

```bash
bash scripts/run_gds_linux_docker.sh
```

To run the full Aura pipeline in Linux Docker with one command:

```bash
bash scripts/run_full_pipeline_linux_docker.sh
```

Optional overrides:

```bash
GDS_VERSION=1.14 bash scripts/run_gds_linux_docker.sh --target auradb-ga --file cypher/04_gds_workflows.cypher
```

Legacy equivalent command:

```bash
tar --exclude=.git --exclude=.venv --exclude=.venv312 --exclude=__pycache__ -cf - . \
| MSYS_NO_PATHCONV=1 docker run --rm -i python:3.12-slim bash -lc "
	set -e
	mkdir -p /work
	tar -C /work -xf -
	cd /work
	python -m pip install --no-cache-dir -r requirements.txt
	python scripts/run_gds.py --target auradb-ga --file cypher/04_gds_workflows.cypher
"
```

Notes:

1. This bypasses Windows TLS/OAuth handshake failures by using Linux networking/SSL stack.
2. If Aura Graph Analytics still fails later due Arrow/projection client behavior, run full pipeline with auto-fallback:

```bash
./.venv312/Scripts/python.exe scripts/run_full_aura_pipeline.py --gds-target auradb-ga --data-dir data --reset
```

The pipeline will switch to AuraDS automatically when `auradb-ga` fails.
