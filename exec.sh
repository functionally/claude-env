#!/usr/bin/env bash
# Exec into a running claude-env pod with the project dev environment pre-activated.
#
# Usage: ./exec.sh [POD_NAME]
#
# POD_NAME defaults to claude-env. Starts at /work with the project's dev shell
# (PATH, CC, PS1, etc.) already set, sourced from /work/dev-env.sh.

set -euo pipefail

POD_NAME="${1:-claude-env}"

podman exec -it -e TERM="$TERM" "${POD_NAME}-claude" \
  bash -c 'source /work/dev-env.sh && cd /work && exec bash -i'
