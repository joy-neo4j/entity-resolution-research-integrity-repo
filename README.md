# Entity Resolution for Research Integrity (Local Neo4j Repo)

This repository packages the model and examples from `Entity_Resolution_Research_Integrity.md` into a local, runnable format.

## What is included

- `cypher/` ordered Cypher scripts for schema, sample graph, ER logic, GDS workflows, and analyst queries
- `data/` sample CSV files (researchers, institutions, papers, patents, drugs, targets, and relationships)
- `docker-compose.yml` for a local Neo4j instance with APOC and GDS
- `scripts/load_all.cypher` one-shot script to load CSV and run setup

## Quick start

1. Start Neo4j:

```bash
docker compose up -d
```

2. Open Neo4j Browser: `http://localhost:7474`

- Username: `neo4j`
- Password: `password1234`

3. Run scripts in order from Neo4j Browser, or use `cypher-shell`:

```bash
cat cypher/01_constraints_indexes.cypher | docker exec -i er-neo4j cypher-shell -u neo4j -p password1234
cat cypher/02_sample_graph.cypher | docker exec -i er-neo4j cypher-shell -u neo4j -p password1234
```

4. Optional CSV load path:

- Place CSV files in Neo4j import mount (already mapped in compose).
- Execute `scripts/load_all.cypher`.

## Script order

1. `cypher/01_constraints_indexes.cypher`
2. `cypher/02_sample_graph.cypher`
3. `cypher/03_entity_resolution_queries.cypher`
4. `cypher/04_gds_workflows.cypher`
5. `cypher/05_integrity_competitive_queries.cypher`

## Notes

- Some queries require APOC and GDS.
- Link prediction examples use alpha pipeline procedures from your source doc. If your GDS version differs, procedure names may need updates.
- This repo is intentionally small and demonstrative, so analysts can adapt it to real feeds (OpenAlex, PubMed, patent data, clinical trials).
