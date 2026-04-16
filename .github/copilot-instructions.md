# Copilot Instructions for this Repository

Use the repository skill at:
- `.github/skills/aura-gds-troubleshooting/SKILL.md`

## Required behavior for Aura/GDS work
- Prefer this skill as the first troubleshooting reference for AuraDB, AuraDS, and Aura Graph Analytics serverless issues.
- When running GDS workflows:
  - Use `scripts/run_gds.py --target auradb-ga` for Aura Graph Analytics serverless sessions.
  - Use `scripts/run_gds.py --target aurads` for AuraDS.
  - Do **not** run GDS procedure files directly via `run_cypher_file.py --target auradb`.
- For Windows TLS/OAuth or Arrow Flight issues, prefer Linux Docker wrappers documented in the skill.

## Query compatibility
- Avoid Cartesian `MATCH (a), (b)` patterns for candidate pairing in ER queries.
- Prefer blocked candidate generation (`collect + UNWIND ranges`, shared identifiers, or shared institutions).
- Use `CALL () { ... }` for subqueries to avoid deprecation warnings.
