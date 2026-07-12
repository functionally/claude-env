
#!/usr/bin/env bash
# Exec into a running claude-env pod with the project dev environment pre-activated.
#
# Usage: ./exec.sh [POD_NAME]
#
# POD_NAME defaults to claude-env. The project is mounted at /work/POD_NAME
# (see play.sh). This starts there, sources the staged dev-env.sh, and drops into
# an interactive shell. Launch `claude` from this directory so its session slug is
# /work/POD_NAME and `claude --resume` scopes to this project only.
 
set -euo pipefail
 
POD_NAME="${1:-claude-env}"
WORK="/work/$POD_NAME"
 
podman exec -it -e TERM="$TERM" "${POD_NAME}-claude" \
  bash -c "source '$WORK/dev-env.sh' && cd '$WORK' && exec bash -i"
