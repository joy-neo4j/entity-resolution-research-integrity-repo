// 5.1 WCC-based golden researcher creation
CALL
  gds.graph.project.cypher(
    'researcher-er',
    'MATCH (r:Researcher) RETURN id(r) AS id',
    'MATCH (r1:Researcher)-[:HAS_ORCID|HAS_EMAIL]->(idNode)<-[:HAS_ORCID|HAS_EMAIL]-(r2:Researcher)
   WHERE id(r1) < id(r2)
   WITH r1, r2, count(DISTINCT idNode) AS idCount
   WHERE idCount >= 1
   RETURN id(r1) AS source, id(r2) AS target, idCount AS weight'
  );

CALL gds.wcc.write('researcher-er', {writeProperty: 'entityId'});

MATCH (r:Researcher)
WHERE r.entityId IS NOT NULL
WITH r.entityId AS eid, collect(r) AS researchers
WHERE size(researchers) > 1
MERGE (g:GoldenResearcher {entityId: eid})
FOREACH (r IN researchers |
  MERGE (r)-[:SAME_AS]->(g)
);

CALL gds.graph.drop('researcher-er', false);

// 5.2 FastRP + KNN
CALL
  gds.graph.project(
    'researcher-knn',
    ['Researcher', 'ORCID', 'Email', 'Institution', 'Paper'],
    {
      HAS_ORCID: {
        orientation: 'UNDIRECTED',
        properties: {weight: {defaultValue: 10.0}}
      },
      HAS_EMAIL: {
        orientation: 'UNDIRECTED',
        properties: {weight: {defaultValue: 5.0}}
      },
      AFFILIATED_WITH: {
        orientation: 'UNDIRECTED',
        properties: {weight: {defaultValue: 2.0}}
      },
      AUTHORED: {
        orientation: 'UNDIRECTED',
        properties: {weight: {defaultValue: 1.0}}
      }
    }
  );

CALL
  gds.fastRP.mutate(
    'researcher-knn',
    {
      mutateProperty: 'embedding',
      embeddingDimension: 128,
      iterationWeights: [0.8, 1.0, 1.0, 1.0],
      normalizationStrength: 0.05,
      randomSeed: 42,
      relationshipWeightProperty: 'weight'
    }
  );

CALL
  gds.knn.mutate(
    'researcher-knn',
    {
      nodeLabels: ['Researcher'],
      nodeProperties: ['embedding'],
      topK: 10,
      mutateRelationshipType: 'KNN_SIM',
      mutateProperty: 'similarity'
    }
  );

CALL gds.graph.drop('researcher-knn', false);

// 5.4 Community detection (co-citation)
MATCH
  (r1:Researcher)-[:AUTHORED]->
  (p1:Paper)-[:CITES]->
  (p2:Paper)<-[:AUTHORED]-
  (r2:Researcher)
WHERE r1 <> r2
WITH r1, r2, count(*) AS citations
MERGE (r1)-[c:CO_CITATION]->(r2)
SET c.strength = citations;

CALL
  gds.graph.project(
    'citation-communities',
    'Researcher',
    {CO_CITATION: {orientation: 'UNDIRECTED', properties: ['strength']}}
  );

CALL
  gds.louvain.stream(
    'citation-communities',
    {relationshipWeightProperty: 'strength'}
  )
  YIELD nodeId, communityId
WITH nodeId, communityId
MATCH (r:Researcher)
WHERE id(r) = nodeId
SET r.communityId = communityId;

CALL gds.graph.drop('citation-communities', false);

// 8.5 PageRank + Betweenness metrics
CALL
  gds.graph.project(
    'cite-net',
    'Researcher',
    {CO_CITATION: {orientation: 'UNDIRECTED', properties: ['strength']}}
  );

CALL
  gds.pageRank.write(
    'cite-net',
    {writeProperty: 'citationPageRank', maxIterations: 20}
  );
CALL gds.betweenness.write('cite-net', {writeProperty: 'citationBetweenness'});
CALL gds.graph.drop('cite-net', false);