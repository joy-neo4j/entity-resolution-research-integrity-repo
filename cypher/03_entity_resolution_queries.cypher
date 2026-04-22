// 4.1 Exact match by shared identifiers
// Relies on write-time normalization: ORCID and Email nodes are MERGED on
// orcidNormalized / emailNormalized (see 01_constraints_indexes.cypher and
// 00_backfill_canonical.cypher), so two researchers sharing a node are
// guaranteed to share the same case-folded identifier.
MATCH
  (r1:Researcher)-[:HAS_ORCID|HAS_EMAIL]->
  (shared)<-[:HAS_ORCID|HAS_EMAIL]-
  (r2:Researcher)
WHERE r1.researcherId < r2.researcherId
RETURN
  r1.researcherId AS researcher_1,
  r1.firstName + ' ' + r1.lastName AS name_1,
  r2.researcherId AS researcher_2,
  r2.firstName + ' ' + r2.lastName AS name_2,
  labels(shared)[0] AS shared_type
ORDER BY researcher_1;

// 4.2 Fuzzy matching with APOC blocked by affiliation
MATCH
  (r1:Researcher)-[:AFFILIATED_WITH]->
  (i:Institution)<-[:AFFILIATED_WITH]-
  (r2:Researcher)
WHERE r1.researcherId < r2.researcherId
WITH
  r1,
  r2,
  apoc.text.jaroWinklerDistance(toLower(r1.firstName), toLower(r2.firstName)) AS first_dist,
  apoc.text.jaroWinklerDistance(toLower(r1.lastName), toLower(r2.lastName)) AS last_dist
WHERE first_dist < 0.50 OR last_dist < 0.25
RETURN
  r1.researcherId AS id_1,
  r2.researcherId AS id_2,
  round(1 - first_dist, 3) AS fn_score,
  round(1 - last_dist, 3) AS ln_score
ORDER BY ln_score DESC, fn_score DESC;

// 4.3 Candidate generation by similar names plus optional co-authorship evidence
MATCH (r:Researcher)
WITH toLower(r.lastName) AS lname, collect(r) AS researchers
WHERE size(researchers) > 1
UNWIND range(0, size(researchers) - 2) AS i
UNWIND range(i + 1, size(researchers) - 1) AS j
WITH researchers[i] AS r1, researchers[j] AS r2
OPTIONAL MATCH (r1)-[:AUTHORED]->(p:Paper)<-[:AUTHORED]-(r2)
WITH
  r1,
  r2,
  collect(p.doi) AS shared_papers,
  apoc.text.jaroWinklerDistance(toLower(r1.firstName), toLower(r2.firstName)) AS fn_dist
WHERE fn_dist < 0.5 OR size(shared_papers) >= 1
RETURN
  r1.researcherId AS id_1,
  r2.researcherId AS id_2,
  size(shared_papers) AS papers_together,
  round(1 - fn_dist, 3) AS fn_score;

// 4.4 Composite confidence score
CALL () {
  MATCH
    (r1:Researcher)-[:HAS_ORCID|HAS_EMAIL]->
    (idNode)<-[:HAS_ORCID|HAS_EMAIL]-
    (r2:Researcher)
  WHERE r1.researcherId < r2.researcherId
  RETURN r1, r2

    UNION
  MATCH
    (r1:Researcher)-[:AFFILIATED_WITH]->
    (:Institution)<-[:AFFILIATED_WITH]-
    (r2:Researcher)
  WHERE r1.researcherId < r2.researcherId
  RETURN r1, r2

    UNION
  MATCH (r:Researcher)
  WITH toLower(r.lastName) AS lname, collect(r) AS researchers
  WHERE size(researchers) > 1
  UNWIND range(0, size(researchers) - 2) AS i
  UNWIND range(i + 1, size(researchers) - 1) AS j
  RETURN researchers[i] AS r1, researchers[j] AS r2
}
WITH DISTINCT r1, r2
WITH
  r1,
  r2,
  apoc.text.jaroWinklerDistance(toLower(r1.firstName), toLower(r2.firstName)) AS fn_dist,
  apoc.text.jaroWinklerDistance(toLower(r1.lastName), toLower(r2.lastName)) AS ln_dist
OPTIONAL MATCH (r1)-[:HAS_ORCID]->(o)<-[:HAS_ORCID]-(r2)
WITH r1, r2, fn_dist, ln_dist, count(o) AS shared_orcids
OPTIONAL MATCH (r1)-[:HAS_EMAIL]->(e)<-[:HAS_EMAIL]-(r2)
WITH r1, r2, fn_dist, ln_dist, shared_orcids, count(e) AS shared_emails
OPTIONAL MATCH (r1)-[:AUTHORED]->(p)<-[:AUTHORED]-(r2)
WITH
  r1,
  r2,
  fn_dist,
  ln_dist,
  shared_orcids,
  shared_emails,
  count(p) AS coauthored
WITH
  r1,
  r2,
  ((1 - fn_dist) * 0.10) +
  ((1 - ln_dist) * 0.10) +
  (CASE
      WHEN shared_orcids > 0 THEN 0.35
      ELSE 0
    END) +
  (CASE
      WHEN shared_emails > 0 THEN 0.20
      ELSE 0
    END) +
  (CASE
      WHEN coauthored > 0 THEN 0.15
      ELSE 0
    END) AS score
WHERE score > 0.25
RETURN
  r1.researcherId AS id_1,
  r2.researcherId AS id_2,
  round(score, 3) AS confidence
ORDER BY score DESC;

// Optional write step: materialize high-confidence SAME_AS links
CALL () {
  MATCH
    (r1:Researcher)-[:HAS_ORCID|HAS_EMAIL]->
    (idNode)<-[:HAS_ORCID|HAS_EMAIL]-
    (r2:Researcher)
  WHERE r1.researcherId < r2.researcherId
  RETURN r1, r2

    UNION
  MATCH
    (r1:Researcher)-[:AFFILIATED_WITH]->
    (:Institution)<-[:AFFILIATED_WITH]-
    (r2:Researcher)
  WHERE r1.researcherId < r2.researcherId
  RETURN r1, r2

    UNION
  MATCH (r:Researcher)
  WITH toLower(r.lastName) AS lname, collect(r) AS researchers
  WHERE size(researchers) > 1
  UNWIND range(0, size(researchers) - 2) AS i
  UNWIND range(i + 1, size(researchers) - 1) AS j
  RETURN researchers[i] AS r1, researchers[j] AS r2
}
WITH DISTINCT r1, r2
WITH
  r1,
  r2,
  apoc.text.jaroWinklerDistance(toLower(r1.firstName), toLower(r2.firstName)) AS fn_dist,
  apoc.text.jaroWinklerDistance(toLower(r1.lastName), toLower(r2.lastName)) AS ln_dist
OPTIONAL MATCH (r1)-[:HAS_ORCID]->(o)<-[:HAS_ORCID]-(r2)
WITH r1, r2, fn_dist, ln_dist, count(o) AS shared_orcids
OPTIONAL MATCH (r1)-[:HAS_EMAIL]->(e)<-[:HAS_EMAIL]-(r2)
WITH r1, r2, fn_dist, ln_dist, shared_orcids, count(e) AS shared_emails
WITH
  r1,
  r2,
  ((1 - fn_dist) * 0.10) +
  ((1 - ln_dist) * 0.10) +
  (CASE
      WHEN shared_orcids > 0 THEN 0.35
      ELSE 0
    END) +
  (CASE
      WHEN shared_emails > 0 THEN 0.20
      ELSE 0
    END) AS score
WHERE score > 0.25
MERGE (r1)-[s:SAME_AS]-(r2)
SET s.score = round(score, 3), s.method = 'composite'
RETURN count(s) AS same_as_links;