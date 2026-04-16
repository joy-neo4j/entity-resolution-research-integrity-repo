import argparse
import inspect
import os
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

from neo4j import GraphDatabase
import requests

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

from run_cypher_file import split_statements


def _is_tls_oauth_failure(exc: Exception) -> bool:
    msg = str(exc).lower()
    needles = [
        "ssl",
        "ssleoferror",
        "unexpected_eof",
        "oauth/token",
        "api.neo4j.io",
        "max retries exceeded",
        "could not finish writing before closing",
    ]
    return any(n in msg for n in needles)


def _is_small_graph_lp_training_failure(exc: Exception) -> bool:
    msg = str(exc).lower()
    return (
        "linkprediction.train" in msg
        and "need at least one model candidate" in msg
    )


def _resolve_aura_project_id(client_id: str, client_secret: str, db_uri: str) -> str:
    instance_id = urlparse(db_uri).hostname.split(".")[0]

    token_resp = requests.post(
        "https://api.neo4j.io/oauth/token",
        data={"grant_type": "client_credentials"},
        auth=(client_id, client_secret),
        verify=False,
        timeout=30,
    )
    token_resp.raise_for_status()
    access_token = token_resp.json()["access_token"]

    instance_resp = requests.get(
        f"https://api.neo4j.io/v1/instances/{instance_id}",
        headers={
            "Authorization": f"Bearer {access_token}",
            "User-agent": "entity-resolution-research-integrity",
        },
        verify=False,
        timeout=30,
    )
    instance_resp.raise_for_status()
    return instance_resp.json()["data"]["tenant_id"]


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

    if args.target == "auradb-ga":
        try:
            sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
            import gds_ssl_fix  # noqa: F401
            from graphdatascience.session import (
                AuraAPICredentials,
                DbmsConnectionInfo,
                GdsSessions,
                SessionMemory,
            )
        except ImportError as exc:
            raise RuntimeError(
                "graphdatascience is required for auradb-ga target. Install dependencies with pip install -r requirements.txt"
            ) from exc

        # graphdatascience 1.20 exposes disable_server_verification under arrow_client,
        # while earlier versions (for example 1.14) do not expose this helper.
        try:
            from graphdatascience.arrow_client.arrow_client_options_util import (
                disable_server_verification,
            )
        except ImportError:
            def disable_server_verification(_arrow_client_options: dict) -> None:
                return

        client_id = os.getenv("AURA_CLIENT_ID")
        client_secret = os.getenv("AURA_CLIENT_SECRET")
        project_id = os.getenv("AURA_PROJECT_ID")

        if not client_id or not client_secret:
            raise RuntimeError(
                "AURA_CLIENT_ID and AURA_CLIENT_SECRET are required for auradb-ga target"
            )

        if not project_id:
            project_id = _resolve_aura_project_id(client_id, client_secret, uri)
            print(f"Resolved Aura project id: {project_id}")

        creds_sig = inspect.signature(AuraAPICredentials)
        if "project_id" in creds_sig.parameters:
            api_credentials = AuraAPICredentials(client_id, client_secret, project_id=project_id)
        else:
            # graphdatascience 1.14 uses tenant_id instead of project_id
            api_credentials = AuraAPICredentials(client_id, client_secret, tenant_id=project_id)

        sessions = GdsSessions(api_credentials=api_credentials)
        db_conn = DbmsConnectionInfo(uri, user, password)
        arrow_client_options = {}
        disable_server_verification(arrow_client_options)

        session_name = f"ri-er-gds-{int(time.time())}"
        get_or_create_sig = inspect.signature(sessions.get_or_create)
        get_or_create_kwargs = {
            "session_name": session_name,
            "memory": SessionMemory.m_8GB,
            "db_connection": db_conn,
        }
        if "arrow_client_options" in get_or_create_sig.parameters:
            get_or_create_kwargs["arrow_client_options"] = arrow_client_options

        gds = sessions.get_or_create(**get_or_create_kwargs)

        # Work around graphdatascience session projection bug where job_id can be a dict,
        # causing `TypeError: unhashable type: 'dict'` in progress tracking.
        try:
            from graphdatascience.query_runner.progress.static_progress_provider import (
                StaticProgressStore,
            )

            original_contains_job_id = StaticProgressStore.contains_job_id

            def safe_contains_job_id(job_id):
                try:
                    return original_contains_job_id(job_id)
                except TypeError:
                    return False

            StaticProgressStore.contains_job_id = staticmethod(safe_contains_job_id)
        except Exception:
            pass

        print(f"Connected to auradb-ga session: {session_name}")

        try:
            if workflow.name != "04_gds_workflows.cypher":
                raise RuntimeError(
                    "auradb-ga currently supports the repository workflow through the native Python implementation for cypher/04_gds_workflows.cypher only"
                )

            gds.run_cypher(
                """
                MATCH (r1:Researcher)-[:HAS_ORCID|HAS_EMAIL]->(idNode)<-[:HAS_ORCID|HAS_EMAIL]-(r2:Researcher)
                WHERE id(r1) < id(r2)
                MERGE (r1)-[rel:ER_MATCH]-(r2)
                SET rel.weight = coalesce(rel.weight, 0) + 1
                """,
                database=database,
            )
            gds.run_cypher("MATCH ()-[r:HAS_ORCID]->() SET r.weight = 10.0", database=database)
            gds.run_cypher("MATCH ()-[r:HAS_EMAIL]->() SET r.weight = 5.0", database=database)
            gds.run_cypher("MATCH ()-[r:AFFILIATED_WITH]->() SET r.weight = 2.0", database=database)
            gds.run_cypher("MATCH ()-[r:AUTHORED]->() SET r.weight = 1.0", database=database)

            gds.run_cypher(
                "MATCH (r1:Researcher)-[rel:CO_CITATION]->(r2:Researcher) DELETE rel",
                database=database,
            )
            gds.run_cypher(
                """
                MATCH (r1:Researcher)-[:AUTHORED]->(p1:Paper)-[:CITES]->(p2:Paper)<-[:AUTHORED]-(r2:Researcher)
                WHERE r1 <> r2
                WITH r1, r2, count(*) AS citations
                MERGE (r1)-[c:CO_CITATION]->(r2)
                SET c.strength = citations
                """,
                database=database,
            )

            for graph_name in ["researcher-er", "researcher-knn", "citation-communities", "cite-net"]:
                try:
                    gds.graph.drop(graph_name, failIfMissing=False)
                except Exception:
                    pass

            researcher_er_projection_query = """
            MATCH (a:Researcher)-[:HAS_ORCID|HAS_EMAIL]->(idNode)<-[:HAS_ORCID|HAS_EMAIL]-(b:Researcher)
            WHERE id(a) < id(b)
            RETURN gds.graph.project.remote(a, b)
            """
            researcher_er_graph, result = gds.graph.project(
                "researcher-er",
                researcher_er_projection_query,
            )
            print(f"[1/4] Projected researcher-er: {result['nodeCount']} nodes")
            gds.wcc.write(researcher_er_graph, writeProperty="entityId")
            gds.run_cypher(
                """
                MATCH (r:Researcher)
                WHERE r.entityId IS NOT NULL
                WITH r.entityId AS eid, collect(r) AS researchers
                WHERE size(researchers) > 1
                MERGE (g:GoldenResearcher {entityId: eid})
                FOREACH (r IN researchers | MERGE (r)-[:SAME_AS]->(g))
                """,
                database=database,
            )
            gds.graph.drop("researcher-er", failIfMissing=False)

            researcher_knn_projection_query = """
            MATCH (a:Researcher)-[:HAS_ORCID|HAS_EMAIL|AFFILIATED_WITH|AUTHORED]->(x)
                  <-[:HAS_ORCID|HAS_EMAIL|AFFILIATED_WITH|AUTHORED]-(b:Researcher)
            WHERE id(a) < id(b)
            RETURN gds.graph.project.remote(a, b)
            """
            researcher_knn_graph, result = gds.graph.project(
                "researcher-knn",
                researcher_knn_projection_query,
            )
            gds.fastRP.mutate(
                researcher_knn_graph,
                mutateProperty="embedding",
                embeddingDimension=128,
                iterationWeights=[0.8, 1.0, 1.0, 1.0],
                normalizationStrength=0.05,
                randomSeed=42,
            )
            gds.knn.mutate(
                researcher_knn_graph,
                nodeProperties=["embedding"],
                topK=10,
                mutateRelationshipType="KNN_SIM",
                mutateProperty="similarity",
            )
            gds.graph.drop("researcher-knn", failIfMissing=False)
            print("[2/4] Completed FastRP + KNN")

            citation_projection_query = """
            MATCH (a:Researcher)-[:CO_CITATION]-(b:Researcher)
            WHERE id(a) < id(b)
            RETURN gds.graph.project.remote(a, b)
            """
            citation_graph, result = gds.graph.project(
                "citation-communities",
                citation_projection_query,
            )
            gds.louvain.write(citation_graph, writeProperty="communityId")
            gds.graph.drop("citation-communities", failIfMissing=False)
            print("[3/4] Completed Louvain community detection")

            cite_net_graph, result = gds.graph.project(
                "cite-net",
                citation_projection_query,
            )
            gds.pageRank.write(cite_net_graph, writeProperty="citationPageRank", maxIterations=20)
            gds.betweenness.write(cite_net_graph, writeProperty="citationBetweenness")
            gds.graph.drop("cite-net", failIfMissing=False)
            print("[4/4] Completed PageRank + Betweenness")
        finally:
            try:
                gds.delete()
                print(f"Deleted auradb-ga session: {session_name}")
            except Exception:
                print(f"Session cleanup skipped for: {session_name}")

    else:
        with GraphDatabase.driver(uri, auth=(user, password)) as driver:
            with driver.session(database=database) as session:
                try:
                    gds_ok = session.run("RETURN gds.version() AS version").single()
                    print(f"Connected. GDS version: {gds_ok['version']}")
                except Exception:
                    print("Connected to aurads")

                for idx, statement in enumerate(statements, 1):
                    try:
                        session.run(statement).consume()
                        print(f"[{idx}/{len(statements)}] OK")
                    except Exception as exc:
                        if _is_small_graph_lp_training_failure(exc):
                            print(
                                f"[{idx}/{len(statements)}] SKIPPED (link prediction training requires a larger candidate set)"
                            )
                            continue
                        raise

    print("GDS workflow completed.")


if __name__ == "__main__":
    main()
