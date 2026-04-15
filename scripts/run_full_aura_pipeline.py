import argparse
import subprocess
import sys
from pathlib import Path


def run_cmd(cmd: list[str], cwd: Path) -> None:
    print("\n$ " + " ".join(cmd))
    result = subprocess.run(cmd, cwd=str(cwd), check=False)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed with exit code {result.returncode}: {' '.join(cmd)}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run full Aura pipeline: schema -> load -> ER/business queries -> GDS"
    )
    parser.add_argument(
        "--gds-target",
        choices=["auradb-ga", "aurads"],
        default="auradb-ga",
        help="Where to run GDS workflows",
    )
    parser.add_argument(
        "--data-dir",
        default="data",
        help="CSV data folder for AuraDB loading",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Delete existing graph before load",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    python_exe = sys.executable

    steps = [
        [
            python_exe,
            "scripts/run_cypher_file.py",
            "--target",
            "auradb",
            "--file",
            "cypher/01_constraints_indexes.cypher",
        ],
        [
            python_exe,
            "scripts/load_data_to_auradb.py",
            "--data-dir",
            args.data_dir,
        ]
        + (["--reset"] if args.reset else []),
        [
            python_exe,
            "scripts/run_cypher_file.py",
            "--target",
            "auradb",
            "--file",
            "cypher/03_entity_resolution_queries.cypher",
        ],
        [
            python_exe,
            "scripts/run_cypher_file.py",
            "--target",
            "auradb",
            "--file",
            "cypher/05_integrity_competitive_queries.cypher",
        ],
        [
            python_exe,
            "scripts/run_gds.py",
            "--target",
            args.gds_target,
            "--file",
            "cypher/04_gds_workflows.cypher",
        ],
    ]

    print("Running full Aura pipeline...")
    print(f"GDS target: {args.gds_target}")

    for i, cmd in enumerate(steps, 1):
        print(f"\n=== Step {i}/{len(steps)} ===")
        run_cmd(cmd, repo_root)

    print("\nPipeline completed successfully.")


if __name__ == "__main__":
    main()
