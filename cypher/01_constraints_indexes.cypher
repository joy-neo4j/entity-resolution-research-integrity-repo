// Constraints
CREATE CONSTRAINT researcher_id IF NOT EXISTS
FOR (r:Researcher)
REQUIRE r.researcherId IS UNIQUE;

CREATE CONSTRAINT orcid_val IF NOT EXISTS
FOR (o:ORCID)
REQUIRE o.value IS UNIQUE;

// Canonical (normalised) forms – the MERGE key for case-insensitive dedup
CREATE CONSTRAINT orcid_normalized IF NOT EXISTS
FOR (o:ORCID)
REQUIRE o.orcidNormalized IS UNIQUE;

CREATE CONSTRAINT email_addr IF NOT EXISTS
FOR (e:Email)
REQUIRE e.address IS UNIQUE;

// Canonical (normalised) forms – the MERGE key for case-insensitive dedup
CREATE CONSTRAINT email_normalized IF NOT EXISTS
FOR (e:Email)
REQUIRE e.emailNormalized IS UNIQUE;

CREATE CONSTRAINT paper_doi IF NOT EXISTS
FOR (p:Paper)
REQUIRE p.doi IS UNIQUE;

CREATE CONSTRAINT patent_num IF NOT EXISTS
FOR (p:Patent)
REQUIRE p.patentNumber IS UNIQUE;

CREATE CONSTRAINT drug_code IF NOT EXISTS
FOR (d:Drug)
REQUIRE d.codeName IS UNIQUE;

// Helpful indexes
CREATE INDEX res_lastname IF NOT EXISTS
FOR (r:Researcher)
ON (r.lastName);
CREATE INDEX res_firstname IF NOT EXISTS
FOR (r:Researcher)
ON (r.firstName);
CREATE INDEX inst_name IF NOT EXISTS
FOR (i:Institution)
ON (i.name);