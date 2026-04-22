// One-time backfill: stamp canonical (lowercased, trimmed) properties onto
// existing Email and ORCID nodes that pre-date the normalised write pattern.
// Safe to re-run (SET is idempotent).

// Backfill Email.emailNormalized from Email.address
MATCH (e:Email)
WHERE e.emailNormalized IS NULL AND e.address IS NOT NULL
SET e.emailNormalized = toLower(trim(e.address))
RETURN count(e) AS emails_backfilled;

// Backfill ORCID.orcidNormalized from ORCID.value
MATCH (o:ORCID)
WHERE o.orcidNormalized IS NULL AND o.value IS NOT NULL
SET o.orcidNormalized = toLower(trim(o.value))
RETURN count(o) AS orcids_backfilled;
