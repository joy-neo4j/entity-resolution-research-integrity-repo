# AuraDB, AuraDS, and GDS Troubleshooting Skill

## Skill Name
`aura-gds-troubleshooting`

## Purpose
Use this skill when:
- Running entity resolution or GDS workflows across AuraDB, Aura Graph Analytics sessions, and AuraDS
- Debugging backend-specific failures (TLS/OAuth, Arrow Flight, projection errors)
- Choosing between AuraDB serverless graph analytics vs AuraDS execution paths
- Configuring version-compatible GDS client code for mixed environments
- Setting up Linux Docker workarounds for Windows TLS issues

## Key Learnings

### 1) Backend behavior differences
- **Aura Graph Analytics (auradb-ga)**: Session-based, can fail independently from AuraDS even when credentials/data are correct
- **AuraDS**: Direct GDS procedure execution, more stable for deterministic CI runs
- **AuraDB**: Transactional workloads, data ingestion, best before GDS moves to analytics instances

### 2) Common failure signatures and their meaning

| Error | Root Cause | Mitigation |
|-------|-----------|-----------|
| `SSLEOFError` / `oauth/token` / `api.neo4j.io` errors | Environment TLS handshake (often Windows/OpenSSL/network path specific) | Use Linux Docker container; apply TLS workaround from `gds_ssl_fix.py` |
| `FlightInternalError: Could not finish writing before closing` | Arrow/Flight transport issue after session creation, typically at projection stage | Refactor to remote query projections; use string-based `gds.graph.project.remote(...)` |
| `TypeError: unhashable type: 'dict'` during projection | Job progress tracking expects hashable types; dict job_id breaks GraphDataScience client | Apply progress-store monkey patch; use version-compatible client signatures |
| `Type mismatch for parameter query expected String but was List<String>` | Remote projection mode requires query string (not native list/dict projections) | Switch to `gds.graph.project.remote("MATCH ... RETURN ...")` pattern |
| `Could not find nodeLabels ... Available labels are __ALL__` | Remote-projected graphs expose `__ALL__` only; explicit filters fail | Remove `nodeLabels=['Researcher']` for remote projections; use `__ALL__` |
| `Need at least one model candidate for training` | Link prediction training candidate set too small for demo data | Treat as non-fatal for sample runs; skip or reduce model training steps |

### 3) Reliable execution strategy

**For Windows environments with TLS/OAuth failures:**
1. Use Linux Docker runner: `bash scripts/run_gds_linux_docker.sh`
2. Or `bash scripts/run_full_pipeline_linux_docker.sh` for complete pipeline

**For Aura Graph Analytics session workflows:**
1. Create projections using query-string remote pattern: `gds.graph.project.remote("MATCH (r:Researcher) RETURN *")`
2. Apply `gds_ssl_fix.py` SSL workaround before session creation
3. Use version-compatible GDS client signatures (check `project_id` vs `tenant_id`, `arrow_client_options` presence)

**For production reliability:**
1. Keep AuraDS fallback enabled in full pipeline (`scripts/run_full_aura_pipeline.py`)
2. Auto-switch to AuraDS if auradb-ga fails on TLS/OAuth or Arrow stages
3. Keep LP (link prediction) training step tolerant for tiny datasets

### 4) Version compatibility guidance

**graphdatascience API differences:**
- `AuraAPICredentials` may require `project_id` (newer) or `tenant_id` (older v1.14)
- `get_or_create()` may or may not support `arrow_client_options` parameter
- `session.run()` return types differ (dict vs object); use runtime type checks

**Recommended pattern for mixed environments:**
```python
try:
    session = GdsSession.get_or_create(
        api_credentials=credentials,
        arrow_client_options=arrow_options  # May not exist in v1.14
    )
except TypeError:
    # v1.14 fallback
    session = GdsSession.get_or_create(api_credentials=credentials)
```

**Linux Docker approach:**
- Use Python 3.12 isolated venv to avoid Windows OpenSSL/pyarrow issues
- Pinned `graphdatascience==1.14` is stable; `1.20+` may have newer API shapes

### 5) File locations in this repository

| File | Purpose |
|------|---------|
| `scripts/run_gds.py` | Base GDS runner; supports `auradb-ga` and `aurads` targets; includes version-compatible session creation |
| `scripts/run_gds_linux_docker.sh` | One-command Linux Docker wrapper for GDS execution (bypasses Windows TLS) |
| `scripts/run_full_pipeline_linux_docker.sh` | One-command Linux Docker for complete pipeline (schema → load → ER → GDS) |
| `scripts/run_full_aura_pipeline.py` | Full pipeline orchestrator with auto-fallback from auradb-ga to aurads on TLS/OAuth/Arrow failures |
| `gds_ssl_fix.py` | TLS/OAuth workaround module; disables cert verification + patches requests for api.neo4j.io |
| `cypher/04_gds_workflows.cypher` | GDS workflow script; uses remote projections compatible with both auradb-ga and aurads |
| `.github/skills/aura-gds-troubleshooting/SKILL.md` | This skill document |

## Operational Checklist

- [ ] **Pre-execution**: Validate required env vars (`AURA_DB_URI`, `AURA_DB_USERNAME`, `AURA_DB_PASSWORD`, `AURA_CLIENT_ID`, `AURA_CLIENT_SECRET` for auradb-ga)
- [ ] **Backend selection**:
  - For GDS on Windows with TLS issues: Use `bash scripts/run_gds_linux_docker.sh --target auradb-ga`
  - For stable GDS execution: Use `aurads` target
  - For full pipeline: Use `bash scripts/run_full_pipeline_linux_docker.sh`
- [ ] **Error recovery**:
  - If auradb-ga fails on TLS/OAuth: Auto-fallback in `run_full_aura_pipeline.py` switches to aurads
  - If auradb-ga fails on Arrow projection: Verify `gds_ssl_fix.py` is applied and retry in Linux container
- [ ] **Verification**:
  - Check final graph outputs exist: `entityId`, `communityId`, citation metrics
  - Confirm GDS algorithm results match expected shapes regardless of backend
- [ ] **Troubleshooting**:
  - See "Common failure signatures" table above for diagnosis and mitigation

## Example: Running GDS on AuraDB Graph Analytics (Windows with TLS workaround)

```bash
# Option 1: Linux Docker one-liner (recommended for Windows)
bash scripts/run_gds_linux_docker.sh --target auradb-ga --file cypher/04_gds_workflows.cypher

# Option 2: Direct Python (if TLS is resolved)
python scripts/run_gds.py --target auradb-ga --file cypher/04_gds_workflows.cypher

# Option 3: Full pipeline with auto-fallback (production)
bash scripts/run_full_pipeline_linux_docker.sh --gds-target auradb-ga --data-dir data --reset
```

## Example: Running GDS on AuraDS (stable alternative)

```bash
# Option 1: Linux Docker
bash scripts/run_gds_linux_docker.sh --target aurads --file cypher/04_gds_workflows.cypher

# Option 2: Direct Python
python scripts/run_gds.py --target aurads --file cypher/04_gds_workflows.cypher

# Option 3: Full pipeline
bash scripts/run_full_pipeline_linux_docker.sh --gds-target aurads --data-dir data --reset
```

## References
- Neo4j Aura documentation: https://neo4j.com/cloud/platform/aura/
- GraphDataScience documentation: https://neo4j.com/docs/graph-data-science/current/
- PyArrow/Flight troubleshooting: https://arrow.apache.org/docs/python/
