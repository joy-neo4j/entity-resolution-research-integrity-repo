"""Minimal GraphRAG retriever example adapted from the source document.

Install:
  pip install neo4j neo4j-graphrag

Set env vars:
  NEO4J_URI=bolt://localhost:7687
  NEO4J_USERNAME=neo4j
  NEO4J_PASSWORD=password1234
"""

import os
from neo4j import GraphDatabase
from neo4j_graphrag.retrievers import HybridCypherRetriever


def main() -> None:
    uri = os.environ.get("NEO4J_URI", "bolt://localhost:7687")
    user = os.environ.get("NEO4J_USERNAME", "neo4j")
    password = os.environ.get("NEO4J_PASSWORD", "password1234")

    driver = GraphDatabase.driver(uri, auth=(user, password))

    retriever = HybridCypherRetriever(
        driver=driver,
        vector_index_name="paper_abstracts",
        fulltext_index_name="paper_fulltext",
        retrieval_query="""
        MATCH (node)<-[:AUTHORED]-(r:Researcher)
        OPTIONAL MATCH (r)-[:AFFILIATED_WITH]->(i:Institution)
        OPTIONAL MATCH (r)-[:AUTHORED]->(other:Paper)
        OPTIONAL MATCH (r)-[:INVENTED]->(pat:Patent)
        RETURN node.title AS paper,
          collect(DISTINCT r.firstName + ' ' + r.lastName) AS authors,
          collect(DISTINCT i.name) AS institutions,
          count(DISTINCT other) AS total_papers,
          collect(DISTINCT pat.patentNumber) AS patents
        """,
    )

    # Indexes must exist to run a real retrieval call.
    print("HybridCypherRetriever initialized successfully.")
    driver.close()


if __name__ == "__main__":
    main()
