# Context Summary from Source Document

This repository is derived from the research note `Entity_Resolution_Research_Integrity.md`.

## Core objective

Unify fragmented researcher, publication, patent, and drug pipeline records into resolved entities for:

- Research integrity analytics (bad actors, citation cartels, paper mills, COI detection)
- Competitive intelligence (researcher-target-drug landscape, institution intelligence, talent movement)

## Main graph entities

- Researcher
- Institution
- Paper
- Patent
- Drug
- Target
- Phenotype
- Company
- ORCID
- Email

## Main relationships

- `AUTHORED`, `INVENTED`, `AFFILIATED_WITH`
- `HAS_ORCID`, `HAS_EMAIL`
- `CITES`
- `STUDIES_TARGET`, `TARGETS`, `HAS_TARGET`, `TREATS`
- `DEVELOPED_BY`, `ASSIGNED_TO`
- `SAME_AS` for entity resolution links

## Resolution approach

1. Deterministic links from shared ORCID/email.
2. Fuzzy matching with APOC string similarity.
3. Graph-based scoring combining identifiers, names, and co-authorship.
4. WCC clustering to generate `GoldenResearcher` entities.
5. Optional GDS embeddings + KNN and community detection for hidden links.

## GenAI and GraphRAG context

- Knowledge graph construction from unstructured text via `neo4j-graphrag`.
- Hybrid retrieval that combines vector/fulltext with Cypher-based graph enrichment.
- Intended analyst-facing natural language workflows over graph context.
