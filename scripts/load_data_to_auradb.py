import argparse
import csv
import os
from pathlib import Path

from neo4j import GraphDatabase

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None


def read_csv(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def run_batch(session, query: str, rows: list[dict], label: str) -> None:
    if not rows:
        print(f"Skip {label}: no rows")
        return

    session.run(query, rows=rows).consume()
    print(f"Loaded {label}: {len(rows)} rows")


def main() -> None:
    parser = argparse.ArgumentParser(description="Load local CSV data into AuraDB using neo4j driver")
    parser.add_argument("--data-dir", default="data", help="Folder containing sample CSV files")
    parser.add_argument("--reset", action="store_true", help="Delete all graph data before loading")
    args = parser.parse_args()

    if load_dotenv is not None:
        load_dotenv()

    uri = os.getenv("AURA_DB_URI") or os.getenv("NEO4J_URI")
    user = os.getenv("AURA_DB_USERNAME") or os.getenv("NEO4J_USER") or os.getenv("NEO4J_USERNAME")
    password = os.getenv("AURA_DB_PASSWORD") or os.getenv("NEO4J_PASSWORD")
    database = os.getenv("AURA_DB_DATABASE") or os.getenv("NEO4J_DATABASE") or "neo4j"

    if not all([uri, user, password]):
        raise RuntimeError("Missing AuraDB connection vars. Check AURA_DB_URI/AURA_DB_USERNAME/AURA_DB_PASSWORD")

    data_dir = Path(args.data_dir)
    if not data_dir.exists():
        raise FileNotFoundError(f"Data directory not found: {data_dir}")

    with GraphDatabase.driver(uri, auth=(user, password)) as driver:
        with driver.session(database=database) as session:
            if args.reset:
                session.run("MATCH (n) DETACH DELETE n").consume()
                print("Graph reset complete.")

            # Constraints and indexes from local cypher file are recommended before load.
            # This loader focuses on data ingestion only.

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (r:Researcher {researcherId: row.researcherId})
                SET r.firstName = row.firstName,
                    r.lastName = row.lastName,
                    r.suffix = row.suffix
                """,
                read_csv(data_dir / "researchers.csv"),
                "researchers",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (i:Institution {instId: row.instId})
                SET i.name = row.name,
                    i.country = row.country,
                    i.city = row.city
                """,
                read_csv(data_dir / "institutions.csv"),
                "institutions",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (p:Paper {doi: row.doi})
                SET p.title = row.title,
                    p.year = toInteger(row.year),
                    p.journal = row.journal
                """,
                read_csv(data_dir / "papers.csv"),
                "papers",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (t:Target {symbol: row.symbol})
                SET t.name = row.name
                """,
                read_csv(data_dir / "targets.csv"),
                "targets",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (ph:Phenotype {phenotypeId: row.phenotypeId})
                SET ph.name = row.name,
                    ph.meshId = row.meshId
                """,
                read_csv(data_dir / "phenotypes.csv"),
                "phenotypes",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (co:Company {companyId: row.companyId})
                SET co.name = row.name,
                    co.country = row.country
                """,
                read_csv(data_dir / "companies.csv"),
                "companies",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (d:Drug {codeName: row.codeName})
                SET d.name = row.name,
                    d.phase = row.phase
                """,
                read_csv(data_dir / "drugs.csv"),
                "drugs",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (pat:Patent {patentNumber: row.patentNumber})
                SET pat.title = row.title,
                    pat.filingDate = date(row.filingDate)
                """,
                read_csv(data_dir / "patents.csv"),
                "patents",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (o:ORCID {value: row.orcid})
                """,
                read_csv(data_dir / "orcids.csv"),
                "orcids",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MERGE (e:Email {address: row.email})
                """,
                read_csv(data_dir / "emails.csv"),
                "emails",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (r:Researcher {researcherId: row.researcherId})
                MATCH (o:ORCID {value: row.orcid})
                MERGE (r)-[:HAS_ORCID]->(o)
                """,
                read_csv(data_dir / "orcids.csv"),
                "rels:HAS_ORCID",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (r:Researcher {researcherId: row.researcherId})
                MATCH (e:Email {address: row.email})
                MERGE (r)-[:HAS_EMAIL]->(e)
                """,
                read_csv(data_dir / "emails.csv"),
                "rels:HAS_EMAIL",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (r:Researcher {researcherId: row.researcherId})
                MATCH (i:Institution {instId: row.instId})
                MERGE (r)-[:AFFILIATED_WITH {year: toInteger(row.year)}]->(i)
                """,
                read_csv(data_dir / "affiliations.csv"),
                "rels:AFFILIATED_WITH",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (r:Researcher {researcherId: row.researcherId})
                MATCH (p:Paper {doi: row.doi})
                MERGE (r)-[:AUTHORED {position: row.position}]->(p)
                """,
                read_csv(data_dir / "authorship.csv"),
                "rels:AUTHORED",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (p1:Paper {doi: row.sourceDoi})
                MATCH (p2:Paper {doi: row.targetDoi})
                MERGE (p1)-[:CITES]->(p2)
                """,
                read_csv(data_dir / "citations.csv"),
                "rels:CITES",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (p:Paper {doi: row.doi})
                MATCH (t:Target {symbol: row.targetSymbol})
                MERGE (p)-[:STUDIES_TARGET]->(t)
                """,
                read_csv(data_dir / "paper_targets.csv"),
                "rels:STUDIES_TARGET",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (d:Drug {codeName: row.codeName})
                MATCH (t:Target {symbol: row.targetSymbol})
                MERGE (d)-[:HAS_TARGET]->(t)
                """,
                read_csv(data_dir / "drug_targets.csv"),
                "rels:HAS_TARGET",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (d:Drug {codeName: row.codeName})
                MATCH (ph:Phenotype {phenotypeId: row.phenotypeId})
                MERGE (d)-[:TREATS]->(ph)
                """,
                read_csv(data_dir / "drug_treats.csv"),
                "rels:TREATS",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (d:Drug {codeName: row.codeName})
                MATCH (co:Company {companyId: row.companyId})
                MERGE (d)-[:DEVELOPED_BY]->(co)
                """,
                read_csv(data_dir / "drug_companies.csv"),
                "rels:DEVELOPED_BY",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (pat:Patent {patentNumber: row.patentNumber})
                MATCH (t:Target {symbol: row.targetSymbol})
                MERGE (pat)-[:TARGETS]->(t)
                """,
                read_csv(data_dir / "patent_targets.csv"),
                "rels:TARGETS",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (pat:Patent {patentNumber: row.patentNumber})
                MATCH (co:Company {companyId: row.companyId})
                MERGE (pat)-[:ASSIGNED_TO]->(co)
                """,
                read_csv(data_dir / "patent_companies.csv"),
                "rels:ASSIGNED_TO",
            )

            run_batch(
                session,
                """
                UNWIND $rows AS row
                MATCH (r:Researcher {researcherId: row.researcherId})
                MATCH (pat:Patent {patentNumber: row.patentNumber})
                MERGE (r)-[:INVENTED]->(pat)
                """,
                read_csv(data_dir / "inventorship.csv"),
                "rels:INVENTED",
            )

    print("AuraDB data load complete.")


if __name__ == "__main__":
    main()
