// 6.1 Bad actor network signal: high mutual citation
MATCH
  (r1:Researcher)-[:AUTHORED]->
  (p1:Paper)-[:CITES]->
  (p2:Paper)<-[:AUTHORED]-
  (r2:Researcher)
WHERE r1 <> r2
WITH r1, r2, count(DISTINCT p1) AS times_cited_them
OPTIONAL MATCH
  (r2)-[:AUTHORED]->(p3:Paper)-[:CITES]->(p4:Paper)<-[:AUTHORED]-(r1)
WITH r1, r2, times_cited_them, count(DISTINCT p3) AS reverse_citations
WHERE times_cited_them > 0 AND reverse_citations >= 0
RETURN
  r1.firstName + ' ' + r1.lastName AS researcher_a,
  r2.firstName + ' ' + r2.lastName AS researcher_b,
  times_cited_them,
  reverse_citations,
  times_cited_them + reverse_citations AS mutual_score
ORDER BY mutual_score DESC;

// 6.2 Citation cartel heuristic by community internal ratio
MATCH
  (m:Researcher)-[:AUTHORED]->
  (p1:Paper)-[:CITES]->
  (p2:Paper)<-[:AUTHORED]-
  (other:Researcher)
OPTIONAL MATCH (m)-[:AFFILIATED_WITH]->(mi:Institution)
OPTIONAL MATCH (other)-[:AFFILIATED_WITH]->(oi:Institution)
WITH
  m,
  other,
  coalesce(toString(m.communityId), mi.name) AS community,
  coalesce(toString(other.communityId), oi.name) AS other_community
WHERE community IS NOT NULL
WITH
  community,
  count(DISTINCT m) AS member_count,
  count(*) AS total_cites,
  sum(
    CASE
      WHEN other_community = community THEN 1
      ELSE 0
    END) AS internal
WITH
  community,
  member_count,
  total_cites AS community_papers,
  CASE
    WHEN total_cites = 0 THEN 0.0
    ELSE toFloat(internal) / total_cites
  END AS internal_ratio
WHERE internal_ratio > 0.0 AND member_count >= 1
RETURN
  community,
  member_count,
  community_papers,
  round(internal_ratio, 3) AS cartel_score
ORDER BY cartel_score DESC;

// 6.3 Paper mill detection heuristic
MATCH (r:Researcher)-[:AUTHORED]->(p:Paper)
OPTIONAL MATCH (r)-[:SAME_AS]->(g:GoldenResearcher)
WITH
  coalesce(g.entityId, r.researcherId) AS entity_key,
  collect(DISTINCT p) AS papers,
  collect(DISTINCT r) AS aliases
WHERE size(papers) >= 1
WITH
  entity_key,
  papers,
  aliases,
  reduce(
    minYear = 9999,
    x IN [p IN papers | p.year] |
      CASE
        WHEN x < minYear THEN x
        ELSE minYear
      END) AS first_year,
  reduce(
    maxYear = 0,
    x IN [p IN papers | p.year] |
      CASE
        WHEN x > maxYear THEN x
        ELSE maxYear
      END) AS last_year
WITH
  entity_key,
  size(papers) AS total,
  size(aliases) AS variants,
  (last_year - first_year + 1) AS years
WHERE years > 0 AND toFloat(total) / years > 0.5
RETURN
  entity_key AS golden_entity,
  total,
  variants,
  years,
  round(toFloat(total) / years, 2) AS papers_per_year
ORDER BY papers_per_year DESC;

// 6.4 Potential undisclosed conflict of interest
MATCH
  (r:Researcher)-[:AUTHORED]->
  (p:Paper)-[:STUDIES_TARGET]->
  (t:Target)<-[:HAS_TARGET]-
  (d:Drug)-[:DEVELOPED_BY]->
  (co:Company)
MATCH (r)-[:INVENTED]->(pat:Patent)-[:ASSIGNED_TO]->(co)
RETURN
  r.firstName + ' ' + r.lastName AS researcher,
  p.title AS paper,
  d.name AS drug,
  co.name AS company,
  pat.patentNumber AS patent,
  t.symbol AS target;

// 7.1 Researcher-target-drug landscape
MATCH (t:Target {symbol: 'HER2'})
OPTIONAL MATCH (t)<-[:STUDIES_TARGET]-(p:Paper)<-[:AUTHORED]-(r:Researcher)
OPTIONAL MATCH (r)-[:AFFILIATED_WITH]->(i:Institution)
OPTIONAL MATCH (t)<-[:HAS_TARGET]-(d:Drug)-[:DEVELOPED_BY]->(co:Company)
RETURN
  t.symbol AS target,
  collect(DISTINCT r.firstName + ' ' + r.lastName) AS researchers,
  collect(DISTINCT i.name) AS institutions,
  collect(DISTINCT d.name + ' (' + d.phase + ')') AS drugs;

// 7.2 Institution intelligence (topic coverage)
MATCH
  (i:Institution)<-[:AFFILIATED_WITH]-
  (r:Researcher)-[:AUTHORED]->
  (p:Paper)-[:STUDIES_TARGET]->
  (t:Target)
WITH i, t.symbol AS topic, count(DISTINCT p) AS papers
RETURN i.name AS institution, i.country AS country, topic, papers
ORDER BY papers DESC
LIMIT 20;

// 7.3 Talent movement tracking
MATCH
  (r:Researcher)-[a1:AFFILIATED_WITH]->(i1:Institution),
  (r)-[a2:AFFILIATED_WITH]->(i2:Institution)
WHERE a1.year < a2.year AND i1 <> i2
RETURN
  r.firstName + ' ' + r.lastName AS researcher,
  i1.name AS from_inst,
  a1.year AS from_year,
  i2.name AS to_inst,
  a2.year AS to_year
ORDER BY to_year DESC;