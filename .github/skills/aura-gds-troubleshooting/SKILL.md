# AuraDB, AuraDS, and GDS Troubleshooting Skill

## Purpose
Use this skill when running entity-resolution or GDS workflows across AuraDB, Aura Graph Analytics sessions, and AuraDS, especially when behavior differs by platform or runtime.

## Key Learnings

### 1) Backend behavior differences
- Aura Graph Analytics session path can fail independently from AuraDS, even when credentials and data are correct.
- AuraDS direct GDS procedure execution is more stable for deterministic CI runs.

### 2) Common failure signatures and meaning
- SSLEOFError / oauth/token / api.neo4j.io errors:
  - Usually environment TLS handshake issues (often Windows/OpenSSL/network path specific).
  - Linux container execution can bypass this class of failures.
- FlightInternalError: Could not finish writing before closing:
  - Arrow/Flight transport issue after session creation, typically projection-stage.
- Type mismatch for parameter query expected String but was List<String>:
  - Remote projection mode expects a projection query string (gds.graph.project.remote pattern), not native list/dict projections.
- Could not find nodeLabels ... Available labels are __ALL__:
  - Remote-projected graphs may expose __ALL__ only; do not force label filters in KNN mutate.
- Need at least one model candidate for training:
  - Link prediction training candidate set is too small in demo data. Treat as non-fatal for sample runs.

### 3) Reliable execution strategy
1. Prefer Linux Docker runner for Aura Graph Analytics session tests when Windows TLS/OAuth errors appear.
2. Use query-string remote projections for session-based graph creation.
3. Keep AuraDS fallback enabled in full pipeline for production reliability.
4. Keep LP-training step tolerant for tiny datasets.

### 4) Version compatibility guidance
- graphdatascience API signatures can differ across versions:
  - AuraAPICredentials may require project_id or tenant_id.
  - get_or_create may or may not support arrow_client_options.
- Write runtime-compatible code using signature checks when supporting mixed environments.

## Operational Checklist
- Validate required env vars for target backend before execution.
- For auradb-ga on Windows, run Linux Docker wrapper first.
- If auradb-ga fails, auto-fallback to aurads and continue pipeline.
- Verify final graph outputs (entityId, communityId, citation metrics) regardless of backend.
