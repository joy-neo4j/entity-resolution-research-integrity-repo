// One-time backfill: stamp canonical (lowercased, trimmed) properties onto
// existing nodes that pre-date the normalised write pattern.
// Safe to re-run (SET is idempotent).

// Backfill Email.emailNormalized from Email.address
MATCH (e:Email)
WHERE e.emailNormalized IS NULL AND e.address IS NOT NULL
SET e.emailNormalized = toLower(trim(e.address))
RETURN count(e) AS emails_backfilled;

// Backfill Researcher.firstNameNormalized / lastNameNormalized
MATCH (r:Researcher)
WHERE r.firstNameNormalized IS NULL AND r.firstName IS NOT NULL
SET r.firstNameNormalized = toLower(trim(r.firstName))
RETURN count(r) AS first_names_backfilled;

MATCH (r:Researcher)
WHERE r.lastNameNormalized IS NULL AND r.lastName IS NOT NULL
SET r.lastNameNormalized = toLower(trim(r.lastName))
RETURN count(r) AS last_names_backfilled;
