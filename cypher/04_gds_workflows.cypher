// 5.1 WCC-based golden researcher creation
// Use native heterogeneous projection so this works in both AuraDS and Aura Graph Analytics.
CALL
  gds.graph.project(
    'researcher-er',
    ['Researcher', 'ORCID', 'Email'],
    {
      HAS_ORCID: {orientation: 'UNDIRECTED'},
      HAS_EMAIL: {orientation: 'UNDIRECTED'}
    }
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
MATCH ()-[r:HAS_ORCID]->()
SET r.weight = 10.0;
MATCH ()-[r:HAS_EMAIL]->()
SET r.weight = 5.0;
MATCH ()-[r:AFFILIATED_WITH]->()
SET r.weight = 2.0;
MATCH ()-[r:AUTHORED]->()
SET r.weight = 1.0;

CALL
  gds.graph.project(
    'researcher-knn',
    ['Researcher', 'ORCID', 'Email', 'Institution', 'Paper'],
    {
      HAS_ORCID: {orientation: 'UNDIRECTED', properties: 'weight'},
      HAS_EMAIL: {orientation: 'UNDIRECTED', properties: 'weight'},
      AFFILIATED_WITH: {orientation: 'UNDIRECTED', properties: 'weight'},
      AUTHORED: {orientation: 'UNDIRECTED', properties: 'weight'}
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

// 5.3 Link Prediction for hidden researcher connections
// Create coauthored relationships from shared paper authorship as LP training target.
MATCH (a:Researcher)-[:AUTHORED]->(p:Paper)<-[:AUTHORED]-(b:Researcher)
WHERE a <> b
MERGE (a)-[:COAUTHORED]-(b);

CALL gds.graph.drop('researcher-lp', false);
CALL gds.pipeline.drop('researcher-lp-pipe', false);
CALL gds.model.drop('researcher-lp-model', false);

CALL
  gds.graph.project(
    'researcher-lp',
    'Researcher',
    {COAUTHORED: {orientation: 'UNDIRECTED'}}
  );

CALL gds.model.drop('researcher-lp-model', false) YIELD modelName;

CALL gds.beta.pipeline.linkPrediction.create('researcher-lp-pipe');

CALL
  gds.beta.pipeline.linkPrediction.addNodeProperty(
    'researcher-lp-pipe',
    'fastRP',
    {embeddingDimension: 128, mutateProperty: 'emb'}
  );

CALL
  gds.beta.pipeline.linkPrediction.addFeature(
    'researcher-lp-pipe',
    'cosine',
    {nodeProperties: ['emb']}
  );

CALL
  gds.beta.pipeline.linkPrediction.train(
    'researcher-lp',
    {
      pipeline: 'researcher-lp-pipe',
      modelName: 'researcher-lp-model',
      targetRelationshipType: 'COAUTHORED',
      metrics: ['AUCPR']
    }
  )
  YIELD modelInfo;

CALL gds.graph.drop('researcher-lp', false);

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