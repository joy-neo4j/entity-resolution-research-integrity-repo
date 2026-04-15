# Entity Resolution for Research Integrity

This repository packages the model and examples from `Entity_Resolution_Research_Integrity.md` into a runnable setup with two supported execution paths:

1. Local Neo4j via Docker
2. Aura-first workflow: load data into AuraDB, then run GDS on either AuraDB Serverless Graph Analytics or AuraDS

## Repository Contents

- `cypher/`: ordered Cypher scripts for schema, sample graph, ER logic, GDS workflows, and analyst queries
- `data/`: sample CSV files
- `scripts/load_all.cypher`: local `file:///` CSV loader (for local Docker Neo4j only)
- `scripts/load_data_to_auradb.py`: Aura-safe loader from local CSVs to AuraDB (driver-based)
- `scripts/run_cypher_file.py`: run any `.cypher` file against AuraDB or AuraDS
- `scripts/run_gds.py`: execute GDS workflow on AuraDB-GA or AuraDS

## Prerequisites

```bash
pip install -r requirements.txt
```

Create and fill `.env` from `.env.example`.

## AuraDB + AuraDS Workflow

### 1. Apply constraints/indexes on AuraDB

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/01_constraints_indexes.cypher
```

### 2. Load local CSVs into AuraDB

```bash
python scripts/load_data_to_auradb.py --data-dir data --reset
```

This replaces `LOAD CSV FROM file:///...` and works with Aura because ingestion is done through the Neo4j driver.

### 3. Run ER and analytics Cypher on AuraDB

```bash
python scripts/run_cypher_file.py --target auradb --file cypher/03_entity_resolution_queries.cypher
python scripts/run_cypher_file.py --target auradb --file cypher/05_integrity_competitive_queries.cypher
```

### 4. Run GDS workflows on either backend

AuraDB Serverless Graph Analytics:

```bash
python scripts/run_gds.py --target auradb-ga --file cypher/04_gds_workflows.cypher
```

AuraDS:

```bash
python scripts/run_gds.py --target aurads --file cypher/04_gds_workflows.cypher
```

### 5. One-command full pipeline

Run everything in sequence: schema, data load, ER/business queries, then GDS.

AuraDB Serverless Graph Analytics:

```bash
python scripts/run_full_aura_pipeline.py --gds-target auradb-ga --data-dir data --reset
```

AuraDS:

```bash
python scripts/run_full_aura_pipeline.py --gds-target aurads --data-dir data --reset
```

## Local Docker Workflow (unchanged)

1. Start local Neo4j:

```bash
docker compose up -d
```

2. Use `scripts/load_all.cypher` only for local Docker Neo4j import volume usage.

## Cypher Script Order

1. `cypher/01_constraints_indexes.cypher`
2. `cypher/02_sample_graph.cypher` (optional shortcut sample load)
3. `cypher/03_entity_resolution_queries.cypher`
4. `cypher/04_gds_workflows.cypher`
5. `cypher/05_integrity_competitive_queries.cypher`

## Notes

- `scripts/load_all.cypher` uses `file:///` and is not for Aura.
- `scripts/load_data_to_auradb.py` is the Aura-compatible ingestion path.
- GDS execution requires the target backend to expose GDS procedures.
