// 4.1 Exact match by shared identifiers
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
WHERE r1.researcherId < r2.researcherId AND NOT (r1)-[:SAME_AS]-(r2)
WITH
  r1,
  r2,
  apoc.text.jaroWinklerDistance(toLower(r1.firstName), toLower(r2.firstName)) AS first_sim,
  apoc.text.jaroWinklerDistance(toLower(r1.lastName), toLower(r2.lastName)) AS last_sim
WHERE first_sim > 0.70 OR last_sim > 0.85
RETURN
  r1.researcherId AS id_1,
  r2.researcherId AS id_2,
  round(first_sim, 3) AS fn_score,
  round(last_sim, 3) AS ln_score
ORDER BY ln_score DESC;

// 4.3 Co-authorship based candidate generation
MATCH (r1:Researcher)-[:AUTHORED]->(p:Paper)<-[:AUTHORED]-(r2:Researcher)
WHERE
  r1.researcherId < r2.researcherId AND
  toLower(r1.lastName) = toLower(r2.lastName)
WITH
  r1,
  r2,
  collect(p.doi) AS shared_papers,
  apoc.text.jaroWinklerDistance(toLower(r1.firstName), toLower(r2.firstName)) AS fn_sim
WHERE fn_sim > 0.6 OR size(shared_papers) >= 2
RETURN
  r1.researcherId AS id_1,
  r2.researcherId AS id_2,
  size(shared_papers) AS papers_together,
  round(fn_sim, 3) AS fn_score;

// 4.4 Composite confidence score
MATCH (r1:Researcher), (r2:Researcher)
WHERE
  r1.researcherId < r2.researcherId AND
  toLower(r1.lastName) = toLower(r2.lastName)
WITH
  r1,
  r2,
  apoc.text.jaroWinklerDistance(toLower(r1.firstName), toLower(r2.firstName)) AS fn,
  apoc.text.jaroWinklerDistance(toLower(r1.lastName), toLower(r2.lastName)) AS ln
OPTIONAL MATCH (r1)-[:HAS_ORCID]->(o)<-[:HAS_ORCID]-(r2)
WITH r1, r2, fn, ln, count(o) AS shared_orcids
OPTIONAL MATCH (r1)-[:HAS_EMAIL]->(e)<-[:HAS_EMAIL]-(r2)
WITH r1, r2, fn, ln, shared_orcids, count(e) AS shared_emails
OPTIONAL MATCH (r1)-[:AUTHORED]->(p)<-[:AUTHORED]-(r2)
WITH r1, r2, fn, ln, shared_orcids, shared_emails, count(p) AS coauthored
WITH
  r1,
  r2,
  (fn * 0.10) +
  (ln * 0.10) +
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
WHERE score > 0.5
RETURN
  r1.researcherId AS id_1,
  r2.researcherId AS id_2,
  round(score, 3) AS confidence
ORDER BY score DESC;

// Optional write step: materialize high-confidence SAME_AS links
MATCH (r1:Researcher), (r2:Researcher)
WHERE
  r1.researcherId < r2.researcherId AND
  toLower(r1.lastName) = toLower(r2.lastName)
WITH
  r1,
  r2,
  apoc.text.jaroWinklerDistance(toLower(r1.firstName), toLower(r2.firstName)) AS fn,
  apoc.text.jaroWinklerDistance(toLower(r1.lastName), toLower(r2.lastName)) AS ln
OPTIONAL MATCH (r1)-[:HAS_ORCID]->(o)<-[:HAS_ORCID]-(r2)
WITH r1, r2, fn, ln, count(o) AS shared_orcids
OPTIONAL MATCH (r1)-[:HAS_EMAIL]->(e)<-[:HAS_EMAIL]-(r2)
WITH r1, r2, fn, ln, shared_orcids, count(e) AS shared_emails
WITH
  r1,
  r2,
  (fn * 0.10) +
  (ln * 0.10) +
  (CASE
      WHEN shared_orcids > 0 THEN 0.35
      ELSE 0
    END) +
  (CASE
      WHEN shared_emails > 0 THEN 0.20
      ELSE 0
    END) AS score
WHERE score > 0.7
MERGE (r1)-[s:SAME_AS]-(r2)
SET s.score = round(score, 3), s.method = 'composite';