#!/usr/bin/env bash
# Start a claude-env pod.
#
# Usage: ./play.sh WORK_DIR [POD_NAME]
#
# WORK_DIR: project directory to mount as /work (defaults to ./work).
#           Resolved to an absolute path so Podman hostPath mounts work without symlinks.
# POD_NAME: name for the pod; must be unique if running multiple pods simultaneously.
#           Defaults to the last component of WORK_DIR.
#
# Tear down with: podman pod stop POD_NAME && podman pod rm POD_NAME

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(realpath "${1:-$SCRIPT_DIR/work}")"
POD_NAME="${2:-$(basename "$WORK_DIR")}"

sed -e "s|name: claude-env|name: $POD_NAME|" \
    -e "s|path: \./work|path: $WORK_DIR|" \
    "$SCRIPT_DIR/claude-env.yaml" \
  | podman kube play --replace=true -
