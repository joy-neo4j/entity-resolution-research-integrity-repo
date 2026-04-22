# Entity Resolution for Research Integrity

This repository implements entity resolution and research integrity workflows with two production paths:

1. AuraDB + Aura Graph Analytics Session (`auradb-ga` via `GdsSessions`)
2. AuraDB + AuraDS (`aurads` direct GDS procedures)

## 1) Repository Layout

- `cypher/00_backfill_canonical.cypher`: one-time backfill to stamp `emailNormalized` / `firstNameNormalized` / `lastNameNormalized` on existing nodes
- `cypher/01_constraints_indexes.cypher`: constraints and indexes (including canonical-property uniqueness)
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

### Step 2A (recommended): Backfill canonical fields for case-insensitive matching

Run this one-time step after loading legacy data to stamp canonical lowercase/trimmed fields used by ER matching.

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/00_backfill_canonical.cypher
```

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

## 7) Running Cypher from VS Code against a Remote Aura Instance

### 7.1 Install the Neo4j VS Code Extension

1. Open the **Extensions** panel (`Ctrl+Shift+X` / `Cmd+Shift+X`).
2. Search for **"Neo4j for VS Code"** (publisher: Neo4j Inc.) and install it.

### 7.2 Add a Connection

1. Click the **Neo4j** icon in the Activity Bar.
2. Click **+ Add Connection** and fill in:
   - **Connect URL**: your Aura Bolt URL, e.g. `neo4j+s://xxxxxxxx.databases.neo4j.io`  
     (copy from the Aura console or `AURA_DB_URI` in your `.env`)
   - **Username**: `neo4j`
   - **Password**: your instance password (`AURA_DB_PASSWORD`)
3. Click **Connect** — the connection turns green when live.

### 7.3 Run a Cypher File

- Open any `.cypher` file in this repo.
- Press `Ctrl+Enter` (Windows/Linux) or `Cmd+Enter` (macOS) to run the **whole file** against the active connection, or select a block of statements first to run only that block.
- Results appear in the **Neo4j Query Results** panel.

> **Tip:** keep a trailing semicolon (`;`) at the end of every Cypher statement.  
> Both the VS Code workflow and Python helpers are safest with explicit semicolon-delimited statements in multi-statement files.

### 7.4 Run via the Python Helper (scripted / CI)

For automation or running files that contain multiple statements you still prefer to use the CLI helper:

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/01_constraints_indexes.cypher
```

This is equivalent to running the file through the extension but returns structured output and exit codes suitable for CI pipelines.

### 7.5 Recommended VS Code Settings (local workspace)

If your workflow excludes `.vscode/settings.json` from source control, create it locally in your workspace with the Copilot skill reference:

```json
{
  "github.copilot.chat.codeGeneration.instructions": [
    {
      "file": "./.github/skills/aura-gds-troubleshooting/SKILL.md"
    }
  ]
}
```

## 8) Troubleshooting

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

6. Disconnected nodes/components appear in graph views:
Expected by design in this sample dataset. Some records are intentionally only lightly connected (or disconnected from specific subdomains) so ER and integrity workflows can be tested across mixed connectivity patterns.

7. Case-sensitive name/email matching misses expected candidates:
Fix by re-running schema + canonical backfill, then re-running ER queries:

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/01_constraints_indexes.cypher
python scripts/run_cypher_file.py --target auradb --file cypher/00_backfill_canonical.cypher
python scripts/run_cypher_file.py --target auradb --file cypher/03_entity_resolution_queries.cypher
```

For future writes/imports, always populate and match on canonical fields (`emailNormalized`, `firstNameNormalized`, `lastNameNormalized`) using `toLower(trim(...))`.

## 9) Compatibility Notes

- `scripts/load_all.cypher` is not Aura-compatible (`file:///` usage).
- `cypher/04_gds_workflows.cypher` uses native projection patterns to avoid `gds.graph.project.cypher` dependency.

## 10) Linux Docker Workaround (Windows TLS/OAuth)

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

## 11) Reload Data from the Remote Repo (No Local Clone)

The CSV dataset lives in `data/` and is committed to the repository, so the
full load pipeline can be re-run directly from the remote repo by any of the
three methods below — no `git clone` required on your workstation.

### 11.1 GitHub Actions — trigger from the GitHub UI or `gh` CLI

Add the workflow definition below as `.github/workflows/reload-data.yml` in
your fork, then follow the setup steps.

<details>
<summary>Workflow YAML (click to expand)</summary>

```yaml
name: Reload sample data into AuraDB

on:
  workflow_dispatch:
    inputs:
      gds_target:
        description: "GDS execution target"
        required: true
        default: "auradb-ga"
        type: choice
        options:
          - auradb-ga
          - aurads
      reset:
        description: "Delete existing graph before loading"
        required: false
        default: true
        type: boolean

jobs:
  reload:
    runs-on: ubuntu-latest

    env:
      AURA_DB_URI: ${{ secrets.AURA_DB_URI }}
      AURA_DB_USERNAME: ${{ secrets.AURA_DB_USERNAME }}
      AURA_DB_PASSWORD: ${{ secrets.AURA_DB_PASSWORD }}
      AURA_DB_DATABASE: ${{ secrets.AURA_DB_DATABASE || 'neo4j' }}
      NEO4J_URI: ${{ secrets.AURA_DB_URI }}
      NEO4J_USER: ${{ secrets.AURA_DB_USERNAME }}
      NEO4J_USERNAME: ${{ secrets.AURA_DB_USERNAME }}
      NEO4J_PASSWORD: ${{ secrets.AURA_DB_PASSWORD }}
      NEO4J_DATABASE: ${{ secrets.AURA_DB_DATABASE || 'neo4j' }}
      AURA_CLIENT_ID: ${{ secrets.AURA_CLIENT_ID }}
      AURA_CLIENT_SECRET: ${{ secrets.AURA_CLIENT_SECRET }}
      AURA_PROJECT_ID: ${{ secrets.AURA_PROJECT_ID }}
      AURA_DS_URI: ${{ secrets.AURA_DS_URI }}
      AURA_DS_USERNAME: ${{ secrets.AURA_DS_USERNAME }}
      AURA_DS_PASSWORD: ${{ secrets.AURA_DS_PASSWORD }}
      AURA_DS_DATABASE: ${{ secrets.AURA_DS_DATABASE || 'neo4j' }}

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip
      - run: pip install --no-cache-dir -r requirements.txt
      - run: python scripts/run_cypher_file.py --target auradb --file cypher/01_constraints_indexes.cypher
      - run: |
          python scripts/load_data_to_auradb.py --target auradb --data-dir data \
            ${{ inputs.reset && '--reset' || '' }}
      - run: python scripts/run_cypher_file.py --target auradb --file cypher/03_entity_resolution_queries.cypher
      - run: python scripts/run_cypher_file.py --target auradb --file cypher/05_integrity_competitive_queries.cypher
      - run: python scripts/run_gds.py --target ${{ inputs.gds_target }} --file cypher/04_gds_workflows.cypher
```

</details>

#### One-time setup (repository Secrets)

Go to **GitHub → Settings → Secrets and variables → Actions** and add the
secrets matching your `.env` values:

| Secret | Description |
|---|---|
| `AURA_DB_URI` | AuraDB Bolt URL |
| `AURA_DB_USERNAME` | AuraDB username |
| `AURA_DB_PASSWORD` | AuraDB password |
| `AURA_DB_DATABASE` | Database name (defaults to `neo4j`) |
| `AURA_CLIENT_ID` | Required for `auradb-ga` GDS target |
| `AURA_CLIENT_SECRET` | Required for `auradb-ga` GDS target |
| `AURA_DS_URI` | Required for `aurads` GDS target |
| `AURA_DS_USERNAME` | Required for `aurads` GDS target |
| `AURA_DS_PASSWORD` | Required for `aurads` GDS target |

#### Trigger from the GitHub UI

1. Open the repository on GitHub.
2. Click **Actions → Reload sample data into AuraDB**.
3. Click **Run workflow**, choose GDS target and whether to reset, then click
   **Run workflow** again.

#### Trigger from the `gh` CLI (no browser needed)

```bash
# Default: auradb-ga target, reset=true
gh workflow run reload-data.yml \
  --repo joy-neo4j/entity-resolution-research-integrity-repo

# AuraDS target, no reset
gh workflow run reload-data.yml \
  --repo joy-neo4j/entity-resolution-research-integrity-repo \
  --field gds_target=aurads \
  --field reset=false
```

### 11.2 Docker one-liner from the GitHub tarball

Downloads the repo as a compressed tarball directly from GitHub and pipes it
into a throwaway Python container — no clone, no local repo needed.

```bash
curl -sL https://github.com/joy-neo4j/entity-resolution-research-integrity-repo/archive/refs/heads/main.tar.gz \
| docker run --rm -i \
  -e AURA_DB_URI="neo4j+s://YOUR_ID.databases.neo4j.io" \
  -e AURA_DB_USERNAME="neo4j" \
  -e AURA_DB_PASSWORD="YOUR_PASSWORD" \
  -e AURA_DB_DATABASE="neo4j" \
  -e AURA_CLIENT_ID="YOUR_CLIENT_ID" \
  -e AURA_CLIENT_SECRET="YOUR_CLIENT_SECRET" \
  python:3.12-slim bash -lc "
    set -e
    mkdir -p /work
    tar -C /work -xzf - --strip-components=1
    cd /work
    pip install --no-cache-dir -r requirements.txt
    python scripts/run_full_aura_pipeline.py --gds-target auradb-ga --data-dir data --reset
  "
```

Alternatively pass credentials from a local `.env` file using `--env-file`:

```bash
curl -sL https://github.com/joy-neo4j/entity-resolution-research-integrity-repo/archive/refs/heads/main.tar.gz \
| docker run --rm -i --env-file .env \
  python:3.12-slim bash -lc "
    set -e
    mkdir -p /work
    tar -C /work -xzf - --strip-components=1
    cd /work
    pip install --no-cache-dir -r requirements.txt
    python scripts/run_full_aura_pipeline.py --gds-target auradb-ga --data-dir data --reset
  "
```

To target a specific branch or tag, replace `main` in the URL:

```
https://github.com/joy-neo4j/entity-resolution-research-integrity-repo/archive/refs/heads/BRANCH.tar.gz
https://github.com/joy-neo4j/entity-resolution-research-integrity-repo/archive/refs/tags/TAG.tar.gz
```

### 11.3 GitHub Codespaces

Codespaces gives you a browser-based VS Code environment pre-cloned from the
remote repo.

1. Open the repository on GitHub.
2. Click **Code → Codespaces → Create codespace on main**.
3. Once the terminal opens inside Codespaces:

```bash
cp .env.example .env
# Edit .env with your credentials (nano / vim / the file explorer)
pip install -r requirements.txt
python scripts/run_full_aura_pipeline.py --gds-target auradb-ga --data-dir data --reset
```

No local disk space or Docker installation required.

## 12) Open in VS Code and Reload Locally

This section covers two VS Code-based approaches: browsing the remote repo
without a full clone (read/edit only) and the recommended path of cloning
locally to run the full pipeline.

### 12.1 Browse the Remote Repo Without Cloning (GitHub Repositories extension)

The **GitHub Repositories** extension lets you open, browse, and edit files
directly from GitHub inside VS Code — no disk clone needed.  
⚠️ Python scripts **cannot be executed** in this mode (no local filesystem or
terminal). Use this for reading and editing files only, then commit back via
the extension's source control panel.

1. Install the **GitHub Repositories** extension (publisher: GitHub) from the
   Extensions panel (`Ctrl+Shift+X` / `Cmd+Shift+X`).
2. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`) and run:
   `Remote Repositories: Open Remote Repository…`
3. Choose **Open Repository from GitHub** and search for
   `joy-neo4j/entity-resolution-research-integrity-repo`.
4. The repo opens in a virtual workspace. Browse `cypher/`, `data/`, and
   `scripts/` without any download.
5. To edit files, make changes and use the **Source Control** panel
   (`Ctrl+Shift+G`) to commit and push back to GitHub.

### 12.2 Clone via VS Code and Reload Locally (full pipeline)

This is the recommended approach when you need to run or regenerate data.

#### Step 1 — Clone the repository

1. Open VS Code.
2. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`) and run:
   `Git: Clone`
3. Enter the repository URL:
   ```
   https://github.com/joy-neo4j/entity-resolution-research-integrity-repo.git
   ```
4. Choose a local folder (e.g. `~/projects/`). VS Code will clone the repo
   and offer to open it — click **Open**.

Alternatively, clone from the terminal and then open the folder:

```bash
git clone https://github.com/joy-neo4j/entity-resolution-research-integrity-repo.git
code entity-resolution-research-integrity-repo
```

#### Step 2 — Open an integrated terminal

Press `` Ctrl+` `` (Windows/Linux) or `` Cmd+` `` (macOS), or go to
**Terminal → New Terminal**.

#### Step 3 — Configure environment variables

```bash
cp .env.example .env
```

Open `.env` in VS Code and fill in your Aura credentials (see Section 3).

#### Step 4 — Create a virtual environment and install dependencies

```bash
python -m venv .venv
# Windows
.\.venv\Scripts\activate
# macOS / Linux
source .venv/bin/activate

pip install -r requirements.txt
```

#### Step 5 — Apply schema

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/01_constraints_indexes.cypher
```

#### Step 6 — Reload sample data (reset + load)

```bash
python scripts/load_data_to_auradb.py --target auradb --data-dir data --reset
```

#### Step 7 — Re-run entity resolution and integrity queries

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/03_entity_resolution_queries.cypher
python scripts/run_cypher_file.py --target auradb --file cypher/05_integrity_competitive_queries.cypher
```

#### Step 8 — Re-run GDS workflows

```bash
# Aura Graph Analytics session
python scripts/run_gds.py --target auradb-ga --file cypher/04_gds_workflows.cypher

# Or AuraDS
python scripts/run_gds.py --target aurads --file cypher/04_gds_workflows.cypher
```

#### One-command alternative (steps 5 – 8 combined)

```bash
python scripts/run_full_aura_pipeline.py --gds-target auradb-ga --data-dir data --reset
```

See Section 5 for full pipeline options and auto-fallback behaviour.
