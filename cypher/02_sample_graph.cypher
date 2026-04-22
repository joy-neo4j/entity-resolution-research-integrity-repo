// Optional: clean slate for demo reruns
MATCH (n)
DETACH DELETE n;

// Researchers (with intended duplicates)
MERGE (r1:Researcher {researcherId: 'RES001'})
SET
  r1.firstName = 'Sarah',
  r1.lastName = 'Chen',
  r1.suffix = 'PhD',
  r1.orcidValue = '0000-0002-1234-5678';

MERGE (r2:Researcher {researcherId: 'RES002'})
SET r2.firstName = 'S.', r2.lastName = 'Chen', r2.suffix = 'Ph.D.';

MERGE (r3:Researcher {researcherId: 'RES003'})
SET r3.firstName = 'Sarah', r3.lastName = 'Chen-Williams', r3.suffix = 'PhD';

MERGE (r4:Researcher {researcherId: 'RES004'})
SET r4.firstName = 'Marco', r4.lastName = 'Rossi', r4.suffix = 'MD PhD';

MERGE (r5:Researcher {researcherId: 'RES005'})
SET r5.firstName = 'M.', r5.lastName = 'Rossi';

MERGE (r6:Researcher {researcherId: 'RES006'})
SET r6.firstName = 'James', r6.lastName = 'Chen', r6.suffix = 'PhD';

// Identifier nodes
MERGE (orcid1:ORCID {value: '0000-0002-1234-5678'});
MERGE (orcid2:ORCID {value: '0000-0003-9876-5432'});
MERGE (email1:Email {address: 'sarah.chen@cambridgepharma.ac.uk'});
MERGE (email2:Email {address: 's.chen@mit.edu'});
MERGE (email3:Email {address: 'marco.rossi@karolinska.se'});
MERGE (email4:Email {address: 'j.chen@stanford.edu'});

MATCH (r1:Researcher {researcherId: 'RES001'}), (orcid1:ORCID {value: '0000-0002-1234-5678'})
MERGE (r1)-[:HAS_ORCID]->(orcid1);

MATCH (r3:Researcher {researcherId: 'RES003'}), (orcid1:ORCID {value: '0000-0002-1234-5678'})
MERGE (r3)-[:HAS_ORCID]->(orcid1);

MATCH (r4:Researcher {researcherId: 'RES004'}), (orcid2:ORCID {value: '0000-0003-9876-5432'})
MERGE (r4)-[:HAS_ORCID]->(orcid2);

MATCH (r1:Researcher {researcherId: 'RES001'}), (email1:Email {address: 'sarah.chen@cambridgepharma.ac.uk'})
MERGE (r1)-[:HAS_EMAIL]->(email1);

MATCH (r2:Researcher {researcherId: 'RES002'}), (email1:Email {address: 'sarah.chen@cambridgepharma.ac.uk'})
MERGE (r2)-[:HAS_EMAIL]->(email1);

MATCH (r3:Researcher {researcherId: 'RES003'}), (email2:Email {address: 's.chen@mit.edu'})
MERGE (r3)-[:HAS_EMAIL]->(email2);

MATCH (r4:Researcher {researcherId: 'RES004'}), (email3:Email {address: 'marco.rossi@karolinska.se'})
MERGE (r4)-[:HAS_EMAIL]->(email3);

MATCH (r5:Researcher {researcherId: 'RES005'}), (email3:Email {address: 'marco.rossi@karolinska.se'})
MERGE (r5)-[:HAS_EMAIL]->(email3);

MATCH (r6:Researcher {researcherId: 'RES006'}), (email4:Email {address: 'j.chen@stanford.edu'})
MERGE (r6)-[:HAS_EMAIL]->(email4);

// Institutions and affiliations
MERGE
  (inst1:Institution {name: 'Cambridge Institute of Therapeutic Innovation'})
SET inst1.country = 'UK', inst1.city = 'Cambridge';

MERGE (inst2:Institution {name: 'MIT Koch Institute for Cancer Research'})
SET inst2.country = 'US', inst2.city = 'Cambridge';

MATCH (r1:Researcher {researcherId: 'RES001'}), (inst1:Institution {name: 'Cambridge Institute of Therapeutic Innovation'})
MERGE (r1)-[:AFFILIATED_WITH {year: 2024}]->(inst1);

MATCH (r2:Researcher {researcherId: 'RES002'}), (inst1:Institution {name: 'Cambridge Institute of Therapeutic Innovation'})
MERGE (r2)-[:AFFILIATED_WITH {year: 2022}]->(inst1);

MATCH (r3:Researcher {researcherId: 'RES003'}), (inst2:Institution {name: 'MIT Koch Institute for Cancer Research'})
MERGE (r3)-[:AFFILIATED_WITH {year: 2025}]->(inst2);

// Papers, target, phenotype, drug, company, patent
MERGE (p1:Paper {doi: '10.1038/s41586-024-0001'})
SET
  p1.title = 'HER2 Amplification Patterns in NSCLC',
  p1.year = 2024,
  p1.journal = 'Nature';

MERGE (p2:Paper {doi: '10.1016/j.cell.2023-0002'})
SET
  p2.title = 'Novel Anti-HER2 ADC Conjugates',
  p2.year = 2023,
  p2.journal = 'Cell';

MERGE (p3:Paper {doi: '10.1126/science.2025-0003'})
SET
  p3.title = 'BRCA1 Synthetic Lethality Screening',
  p3.year = 2025,
  p3.journal = 'Science';

MERGE (t1:Target {symbol: 'HER2'})
SET t1.name = 'Human Epidermal Growth Factor Receptor 2';

MERGE (t2:Target {symbol: 'BRCA1'})
SET t2.name = 'Breast Cancer Type 1 Susceptibility Protein';

MERGE (ph1:Phenotype {name: 'Non-Small Cell Lung Cancer'})
SET ph1.meshId = 'D002289';

MERGE (d1:Drug {codeName: 'T-DXd'})
SET d1.name = 'Trastuzumab deruxtecan', d1.phase = 'Approved';

MERGE (co1:Company {name: 'Daiichi Sankyo'})
SET co1.country = 'JP';

MERGE (pat1:Patent {patentNumber: 'US20240001A1'})
SET
  pat1.title = 'Anti-HER2 Antibody Drug Conjugate',
  pat1.filingDate = date('2023-06-15');

// Graph links
MATCH (r1:Researcher {researcherId: 'RES001'}), (p1:Paper {doi: '10.1038/s41586-024-0001'})
MERGE (r1)-[:AUTHORED {position: 'first'}]->(p1);

MATCH (r2:Researcher {researcherId: 'RES002'}), (p2:Paper {doi: '10.1016/j.cell.2023-0002'})
MERGE (r2)-[:AUTHORED {position: 'corresponding'}]->(p2);

MATCH (r4:Researcher {researcherId: 'RES004'}), (p1:Paper {doi: '10.1038/s41586-024-0001'})
MERGE (r4)-[:AUTHORED {position: 'last'}]->(p1);

MATCH (r5:Researcher {researcherId: 'RES005'}), (p2:Paper {doi: '10.1016/j.cell.2023-0002'})
MERGE (r5)-[:AUTHORED {position: 'first'}]->(p2);

MATCH (r3:Researcher {researcherId: 'RES003'}), (p3:Paper {doi: '10.1126/science.2025-0003'})
MERGE (r3)-[:AUTHORED {position: 'first'}]->(p3);

MATCH (p2:Paper {doi: '10.1016/j.cell.2023-0002'}), (p1:Paper {doi: '10.1038/s41586-024-0001'})
MERGE (p2)-[:CITES]->(p1);

MATCH (p3:Paper {doi: '10.1126/science.2025-0003'}), (p1:Paper {doi: '10.1038/s41586-024-0001'})
MERGE (p3)-[:CITES]->(p1);

MATCH (p1:Paper {doi: '10.1038/s41586-024-0001'}), (t1:Target {symbol: 'HER2'})
MERGE (p1)-[:STUDIES_TARGET]->(t1);

MATCH (p2:Paper {doi: '10.1016/j.cell.2023-0002'}), (t1:Target {symbol: 'HER2'})
MERGE (p2)-[:STUDIES_TARGET]->(t1);

MATCH (p3:Paper {doi: '10.1126/science.2025-0003'}), (t2:Target {symbol: 'BRCA1'})
MERGE (p3)-[:STUDIES_TARGET]->(t2);

MATCH (d1:Drug {codeName: 'T-DXd'}), (t1:Target {symbol: 'HER2'})
MERGE (d1)-[:HAS_TARGET]->(t1);

MATCH (d1:Drug {codeName: 'T-DXd'}), (ph1:Phenotype {name: 'Non-Small Cell Lung Cancer'})
MERGE (d1)-[:TREATS]->(ph1);

MATCH (d1:Drug {codeName: 'T-DXd'}), (co1:Company {name: 'Daiichi Sankyo'})
MERGE (d1)-[:DEVELOPED_BY]->(co1);

MATCH (pat1:Patent {patentNumber: 'US20240001A1'}), (t1:Target {symbol: 'HER2'})
MERGE (pat1)-[:TARGETS]->(t1);

MATCH (pat1:Patent {patentNumber: 'US20240001A1'}), (co1:Company {name: 'Daiichi Sankyo'})
MERGE (pat1)-[:ASSIGNED_TO]->(co1);

MATCH (r1:Researcher {researcherId: 'RES001'}), (pat1:Patent {patentNumber: 'US20240001A1'})
MERGE (r1)-[:INVENTED]->(pat1);