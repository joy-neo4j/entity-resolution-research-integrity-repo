import argparse
import subprocess
import sys
from pathlib import Path


def run_cmd(cmd: list[str], cwd: Path) -> None:
    print("\n$ " + " ".join(cmd))
    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        check=False,
        capture_output=True,
        text=True,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed with exit code {result.returncode}: {' '.join(cmd)}\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )


def is_tls_oauth_failure(err: Exception) -> bool:
    msg = str(err).lower()
    needles = [
        "ssleoferror",
        "unexpected_eof",
        "oauth/token",
        "api.neo4j.io",
        "could not finish writing before closing",
        "max retries exceeded",
    ]
    return any(n in msg for n in needles)


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
            "--target",
            "auradb",
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

    if args.gds_target == "aurads":
        steps.insert(
            4,
            [
                python_exe,
                "scripts/load_data_to_auradb.py",
                "--target",
                "aurads",
                "--data-dir",
                args.data_dir,
            ] + (["--reset"] if args.reset else []),
        )

    print("Running full Aura pipeline...")
    print(f"GDS target: {args.gds_target}")

    for i, cmd in enumerate(steps, 1):
        print(f"\n=== Step {i}/{len(steps)} ===")
        try:
            run_cmd(cmd, repo_root)
        except RuntimeError as err:
            is_gds_step = "scripts/run_gds.py" in " ".join(cmd)
            if args.gds_target == "auradb-ga" and is_gds_step and is_tls_oauth_failure(err):
                print("\nAura Graph Analytics TLS/OAuth failure detected. Falling back to AuraDS...")

                fallback_steps = [
                    [
                        python_exe,
                        "scripts/load_data_to_auradb.py",
                        "--target",
                        "aurads",
                        "--data-dir",
                        args.data_dir,
                    ] + (["--reset"] if args.reset else []),
                    [
                        python_exe,
                        "scripts/run_gds.py",
                        "--target",
                        "aurads",
                        "--file",
                        "cypher/04_gds_workflows.cypher",
                    ],
                ]

                for f_idx, f_cmd in enumerate(fallback_steps, 1):
                    print(f"\n--- Fallback Step {f_idx}/{len(fallback_steps)} ---")
                    run_cmd(f_cmd, repo_root)
                continue

            raise

    print("\nPipeline completed successfully.")


if __name__ == "__main__":
    main()
