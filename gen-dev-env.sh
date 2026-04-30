#!/usr/bin/env bash
# Generate dev-env.sh inside the project directory for use inside the container.
#
# Usage: ./gen-dev-env.sh [FLAKE_PATH]
#
# FLAKE_PATH is the path to a flake on the host whose devShell you want
# available inside the container. Defaults to ./work. The path is resolved
# to an absolute path before being passed to nix, so a leading ./ is not required.
#
# Run this from anywhere whenever the flake's inputs change, then
# source /work/dev-env.sh inside the container to activate the environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE="$(realpath "${1:-"$SCRIPT_DIR/work"}")"
OUTPUT="$FLAKE/dev-env.sh"

echo "Generating dev env from $FLAKE ..." >&2
nix print-dev-env "$FLAKE" > "$OUTPUT"
echo "Done. Inside the container, run: source /work/dev-env.sh" >&2
