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
WHERE times_cited_them > 1 AND reverse_citations > 1
RETURN
  r1.firstName + ' ' + r1.lastName AS researcher_a,
  r2.firstName + ' ' + r2.lastName AS researcher_b,
  times_cited_them,
  reverse_citations,
  times_cited_them + reverse_citations AS mutual_score
ORDER BY mutual_score DESC;

// 6.2 Citation cartel heuristic by community internal ratio
MATCH (r:Researcher)-[:AUTHORED]->(p:Paper)
WITH r, count(p) AS total_papers, r.communityId AS community
WHERE community IS NOT NULL
WITH community, collect(r) AS members, sum(total_papers) AS community_papers
UNWIND members AS m
MATCH
  (m)-[:AUTHORED]->
  (p1:Paper)-[:CITES]->
  (p2:Paper)<-[:AUTHORED]-
  (other:Researcher)
WITH
  community,
  community_papers,
  size(members) AS member_count,
  sum(
    CASE
      WHEN other.communityId = community THEN 1
      ELSE 0
    END) AS internal,
  count(*) AS total_cites
WITH
  community,
  member_count,
  community_papers,
  CASE
    WHEN total_cites = 0 THEN 0.0
    ELSE toFloat(internal) / total_cites
  END AS internal_ratio
WHERE internal_ratio > 0.7 AND member_count >= 2
RETURN
  community,
  member_count,
  community_papers,
  round(internal_ratio, 3) AS cartel_score
ORDER BY cartel_score DESC;

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