
#!/usr/bin/env bash
# Start a claude-env pod.
#
# Usage: ./play.sh WORK_DIR [POD_NAME]
#
# WORK_DIR: project directory to mount. Resolved to an absolute host path.
# POD_NAME: pod name; must be unique per running pod. Defaults to basename WORK_DIR.
#
# The project is mounted at /work/POD_NAME inside the container (NOT bare /work),
# so each project gets a distinct path, and therefore a distinct Claude Code
# session slug under the shared ~/.claude/projects/. Sessions all live in the one
# shared home (browsable/back-up-able in one place) but `claude --resume` launched
# from /work/POD_NAME only ever sees that project's own sessions.
#
# Tear down with: podman pod stop POD_NAME && podman pod rm POD_NAME
 
set -euo pipefail
 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(realpath "${1:-$SCRIPT_DIR/work}")"
POD_NAME="${2:-$(basename "$WORK_DIR")}"
MOUNT_PATH="/work/$POD_NAME"
 
sed -e "s|name: claude-env|name: $POD_NAME|" \
    -e "s|path: \./work|path: $WORK_DIR|" \
    -e "s|mountPath: /work|mountPath: $MOUNT_PATH|" \
    "$SCRIPT_DIR/claude-env.yaml" \
  | podman kube play --replace=true -
