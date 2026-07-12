#!/usr/bin/env bash
# Generate dev-env.sh for a project, from a flake that may live ELSEWHERE.
#
# Usage: ./gen-dev-env.sh FLAKE_PATH PROJECT_DIR
#
# FLAKE_PATH:  host path to a flake whose devShell you want in the container.
#              May be a shared parent flake used by many projects.
# PROJECT_DIR: the project directory that play.sh mounts as /work/POD_NAME.
#              dev-env.sh is written here so it appears at /work/POD_NAME/dev-env.sh.
#
# Decoupling the flake from the project lets many projects share one flake:
#   ./gen-dev-env.sh /path/to/shared-flake /path/to/projectA
#   ./gen-dev-env.sh /path/to/shared-flake /path/to/projectB
#
# Re-run whenever the flake's inputs change.
 
set -euo pipefail
 
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 FLAKE_PATH PROJECT_DIR" >&2
  exit 1
fi
 
FLAKE="$(realpath "$1")"
PROJECT_DIR="$(realpath "$2")"
OUTPUT="$PROJECT_DIR/dev-env.sh"
 
echo "Generating dev env from $FLAKE into $OUTPUT ..." >&2
nix print-dev-env "$FLAKE" > "$OUTPUT"
echo "Done. Inside the container: source /work/<pod>/dev-env.sh (exec.sh does this)." >&2
