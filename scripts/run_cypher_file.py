import argparse
import os
from pathlib import Path

from neo4j import GraphDatabase

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None


def split_statements(text: str) -> list[str]:
    statements = []
    current = []
    in_single = False
    in_double = False
    in_backtick = False

    for ch in text:
        if ch == "'" and not in_double and not in_backtick:
            in_single = not in_single
        elif ch == '"' and not in_single and not in_backtick:
            in_double = not in_double
        elif ch == "`" and not in_single and not in_double:
            in_backtick = not in_backtick

        if ch == ";" and not (in_single or in_double or in_backtick):
            statement = "".join(current).strip()
            if statement:
                statements.append(statement)
            current = []
        else:
            current.append(ch)

    trailing = "".join(current).strip()
    if trailing:
        statements.append(trailing)

    return statements


def env_for_target(target: str) -> tuple[str, str, str, str]:
    if target == "auradb":
        uri = os.getenv("AURA_DB_URI") or os.getenv("NEO4J_URI")
        user = os.getenv("AURA_DB_USERNAME") or os.getenv("NEO4J_USER") or os.getenv("NEO4J_USERNAME")
        password = os.getenv("AURA_DB_PASSWORD") or os.getenv("NEO4J_PASSWORD")
        database = os.getenv("AURA_DB_DATABASE") or os.getenv("NEO4J_DATABASE") or "neo4j"
    elif target == "aurads":
        uri = os.getenv("AURA_DS_URI")
        user = os.getenv("AURA_DS_USERNAME") or os.getenv("AURA_DB_USERNAME") or os.getenv("NEO4J_USER") or os.getenv("NEO4J_USERNAME")
        password = os.getenv("AURA_DS_PASSWORD")
        database = os.getenv("AURA_DS_DATABASE") or "neo4j"
    else:
        raise ValueError(f"Unsupported target: {target}")

    if not all([uri, user, password, database]):
        raise RuntimeError(
            f"Missing connection env vars for target={target}. Check your .env configuration."
        )

    return uri, user, password, database


def run_file(cypher_file: Path, target: str) -> None:
    if load_dotenv is not None:
        load_dotenv()

    uri, user, password, database = env_for_target(target)

    text = cypher_file.read_text(encoding="utf-8")
    statements = split_statements(text)

    if not statements:
        print(f"No statements found in {cypher_file}")
        return

    print(f"Running {len(statements)} statements from {cypher_file} on {target} ({database})")

    with GraphDatabase.driver(uri, auth=(user, password)) as driver:
        with driver.session(database=database) as session:
            for i, stmt in enumerate(statements, 1):
                session.run(stmt).consume()
                print(f"[{i}/{len(statements)}] OK")

    print("Completed.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a .cypher file against AuraDB or AuraDS")
    parser.add_argument("--target", choices=["auradb", "aurads"], required=True)
    parser.add_argument("--file", required=True, help="Path to .cypher file")
    args = parser.parse_args()

    run_file(Path(args.file), args.target)


if __name__ == "__main__":
    main()
