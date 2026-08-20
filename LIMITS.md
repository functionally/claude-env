# LIMITS.md — hard limits of a claude-env container

Canonical, agent-addressed statement of what a claude-env container can and cannot do. **Copy this section into each project's `AGENTS.md` (or link it) so agents learn the limits at the point of use rather than by probing.** The limits follow from `claude-env.yaml`, `gen-dev-env.sh`, and `exec.sh`; if those change, change this file in the same commit.

You are running in a rootless Podman container. The host's Nix store and profiles are mounted **read-only**, no Nix daemon socket is mounted, all capabilities are dropped, and privilege escalation is disabled. Your shell environment is a **snapshot**: `gen-dev-env.sh` runs `nix print-dev-env` on the *host* and writes `dev-env.sh`, which `exec.sh` sources on entry. The container never evaluates flakes.

## Invariants

1. **The Nix store is read-only and there is no daemon.** Every Nix operation that writes, fetches, builds, or locks fails — `nix build`, `nix run`, `nix develop`, `nix flake lock`, `nix flake update`, `nix flake check`, `nix-env`. **Never attempt to remount the store or otherwise escalate privileges**: capabilities are dropped, it cannot succeed, and the attempt is misbehavior, not measurement. `statix check` and other pure text analysis are the only in-container flake verification.
2. **The environment is exactly what the flake put on PATH.** The mounted host store contains far more than the project's toolchain — all readable, none of it in contract. **Do not scavenge the store**: no `find /nix/store` to locate and run tools that are not on PATH. Off-PATH tools bypass the flake, and therefore reproducibility and the human's change control.
3. **A missing tool is a flake edit plus a request, never a workaround.** Add the package to the project flake's dev shell (with a comment saying what it is for), then ask the human to run the host-side cycle: build if the flake needs new packages (`nix develop` or `nix build` on the host), regenerate the snapshot (`./gen-dev-env.sh FLAKE_PATH PROJECT_DIR` — this also updates `flake.lock` when inputs changed), and re-enter (`./exec.sh POD_NAME`). Nothing inside the session can refresh the environment.
4. **Writable paths are `/home/claude` and the project mount (`/work/POD_NAME`) only.** Other host paths and sibling projects are not mounted and not visible. Absolute paths differ between host and container views of the same tree, so artifacts that bake absolute paths at creation time (Python venvs, compile-time path captures) work on one side only — create them from the side that consumes them.
5. **There is no `/usr/bin/env`.** Scripts with `#!/usr/bin/env …` shebangs fail with "bad interpreter"; invoke them as `bash script.sh`, `python3 script.py`, and so on.
6. **Network access is whatever the pod's network provides; the TLS trust root is the bundled CA certificates** (`SSL_CERT_FILE` is preset). No package manager works at runtime — no `apt`, `pip install --user`, `npm install -g`; language-level project-local installs into the writable project mount are a project-policy question, not a container limit.

## Probe etiquette

A denied operation against these enforced limits costs seconds and settles a fact — probing them once is legitimate. Never re-probe a limit already documented, never attempt escalation, and never probe anything whose *success* would be the damage (posting, sending, spending, mutating shared state).
