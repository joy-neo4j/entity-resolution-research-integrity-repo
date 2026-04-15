import argparse
import os
from pathlib import Path

from neo4j import GraphDatabase

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

from run_cypher_file import split_statements


def connect_from_env(target: str) -> tuple[str, str, str, str]:
    if target == "aurads":
        uri = os.getenv("AURA_DS_URI")
        user = os.getenv("AURA_DS_USERNAME") or os.getenv("AURA_DB_USERNAME") or os.getenv("NEO4J_USER") or os.getenv("NEO4J_USERNAME")
        password = os.getenv("AURA_DS_PASSWORD")
        database = os.getenv("AURA_DS_DATABASE") or "neo4j"
    elif target == "auradb-ga":
        uri = os.getenv("AURA_DB_URI") or os.getenv("NEO4J_URI")
        user = os.getenv("AURA_DB_USERNAME") or os.getenv("NEO4J_USER") or os.getenv("NEO4J_USERNAME")
        password = os.getenv("AURA_DB_PASSWORD") or os.getenv("NEO4J_PASSWORD")
        database = os.getenv("AURA_DB_DATABASE") or os.getenv("NEO4J_DATABASE") or "neo4j"
    else:
        raise ValueError(f"Unsupported target {target}")

    if not all([uri, user, password, database]):
        raise RuntimeError(f"Missing env vars for target={target}")

    return uri, user, password, database


def main() -> None:
    parser = argparse.ArgumentParser(description="Run GDS workflows on AuraDS or AuraDB serverless graph analytics")
    parser.add_argument(
        "--target",
        choices=["aurads", "auradb-ga"],
        required=True,
        help="aurads = AuraDS instance, auradb-ga = AuraDB with serverless graph analytics",
    )
    parser.add_argument(
        "--file",
        default="cypher/04_gds_workflows.cypher",
        help="Cypher workflow file to execute",
    )
    args = parser.parse_args()

    if load_dotenv is not None:
        load_dotenv()

    uri, user, password, database = connect_from_env(args.target)

    workflow = Path(args.file)
    statements = split_statements(workflow.read_text(encoding="utf-8"))

    print(f"Running {len(statements)} GDS statements on {args.target} ({database})")

    with GraphDatabase.driver(uri, auth=(user, password)) as driver:
        with driver.session(database=database) as session:
            gds_ok = session.run("RETURN gds.version() AS version").single()
            print(f"Connected. GDS version: {gds_ok['version']}")

            for idx, statement in enumerate(statements, 1):
                session.run(statement).consume()
                print(f"[{idx}/{len(statements)}] OK")

    print("GDS workflow completed.")


if __name__ == "__main__":
    main()
