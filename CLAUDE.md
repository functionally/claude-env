# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repository builds a secure Podman-based container for running Claude Code. The container is a minimal NixOS 25.11 image with Claude Code running as the host user (rootless Podman maps container UID 0 to the host user on disk).

## Key files

| File | Role |
|---|---|
| `flake.nix` | Defines `packages.container` (image build) and dev shell |
| `claude-env.yaml` | Podman kube file — volumes, security context |

## Building the container

```bash
nix build                    # produces ./result (OCI tar); .#container also works
podman load < result         # imports as localhost/claude-env:latest
```

`packages.default` / `packages.container` are only available on Linux.

## Running the container

One-time setup:

```bash
mkdir -p claude/.claude
cp ~/.claude/.credentials.json claude/.claude/.credentials.json
```

Before starting, generate the dev environment script on the host. `gen-dev-env.sh` takes **two** arguments — the flake and the project directory — so the flake providing the dev shell need not live inside the project (one shared flake can serve many projects):

```bash
# gen-dev-env.sh FLAKE_PATH PROJECT_DIR
./gen-dev-env.sh examples/rust examples/rust           # flake and project coincide
./gen-dev-env.sh /path/to/shared-flake /path/to/proj   # one shared flake, any project
```

`dev-env.sh` is written into `PROJECT_DIR`, so it appears in the container at `/work/POD_NAME/dev-env.sh`.

Start a pod (pod name defaults to the last path component of the work directory):

```bash
./play.sh examples/rust             # pod named "rust", mounted at /work/rust
./play.sh /path/to/project mypod    # explicit pod name, mounted at /work/mypod
```

The project is mounted at `/work/POD_NAME` (not bare `/work`), giving each project a distinct in-container path and therefore a distinct Claude Code session slug.

Enter the container — sources `/work/POD_NAME/dev-env.sh`, cds to `/work/POD_NAME`, drops to an interactive shell:

```bash
./exec.sh rust     # pod name matches what was passed to play.sh
```

Launch `claude` from `/work/POD_NAME` (where `exec.sh` leaves you), not a subdirectory: Claude Code keys session history to the launch directory, so `cd`-ing deeper before running `claude` forks the session bucket and breaks `claude --resume`.

Tear down:

```bash
podman pod stop rust && podman pod rm rust
```

Multiple pods with different projects can run simultaneously; each has its own name, its own `/work/POD_NAME` mount, and its own `dev-env.sh`. Project files are isolated by the mount; session history is shared in the one home but scoped per project on resume (see Architecture).

## Architecture

**`packages.container` (flake.nix):**

`pkgs.buildEnv` merges all tools into a single environment at the image root. Static `/etc/passwd`, `/etc/group`, `/etc/resolv.conf`, `/etc/hosts`, and `/etc/hostname` are created via `pkgs.writeTextDir` and passed as separate items in `contents` — no `fakeRootCommands` or fakeroot required. `/home/claude/.claude` is pre-created via `extraCommands`. `pkgs.cacert` provides the CA bundle; `SSL_CERT_FILE` and `NIX_SSL_CERT_FILE` point at it so Node.js (Claude Code's OAuth token refresh) can verify TLS.

**UID mapping:** Container UID 0 maps to the host user in rootless Podman. No `keep-id` annotation is needed. Files written inside the container appear owned by the host user.

**Volume layout:**

| Container path | Source | Purpose |
|---|---|---|
| `/home/claude` | `./claude/` | Claude Code state (credentials, settings, history) |
| `/work/POD_NAME` | host path passed to `play.sh` | Development project; also contains `dev-env.sh` |
| `/nix/store` | `/nix/store` (host, read-only) | Pre-built derivations referenced by `dev-env.sh` |
| `/nix/var/nix/profiles` | host, read-only | Nix profile binaries |

No daemon socket is mounted. The container can read the host store but cannot build, delete, or GC. The entire `claude/` directory is `.gitignore`d.

**Credentials:** OAuth credentials live in `claude/.claude/.credentials.json` (copied from `~/.claude/.credentials.json` on first setup).

**Session model (shared store, per-project scope):** `CLAUDE_CONFIG_DIR` is left at its default, so Claude Code's config root is the shared home at `/home/claude/.claude`. Account state (credentials, global settings such as the status line) and all session history therefore live in one place, shared across every pod started from this clone. Isolation between projects comes from two independent mechanisms:

- **Project files** are isolated by the mount — a pod sees only its own `/work/POD_NAME`, never another project's directory.
- **Sessions** are isolated by the path slug. Because each project is mounted at a distinct `/work/POD_NAME` and `claude` is launched from there, Claude Code files each project's transcripts under a distinct slug in `/home/claude/.claude/projects/`. `claude --resume` from `/work/POD_NAME` lists only that project's sessions, yet all transcripts remain in the single shared home for browsing or backup.

This is why the mount path is `/work/POD_NAME` rather than bare `/work`: mounting every project at the same path would collapse them into one slug and let `--resume` mix sessions across projects. To keep work and personal accounts separate, clone this repository twice and seed each clone's `claude/.claude/` with the matching credentials.

**Sandbox:** `enableWeakerNestedSandbox: true` is set in `claude/.claude/settings.json` because bubblewrap's nested user-namespace setup hangs inside a rootless Podman container.

## Nix access inside the container

The container mounts the host Nix store and profiles read-only. No daemon socket is mounted. Dev shell environments are injected via `gen-dev-env.sh` / `exec.sh` (the `nix print-dev-env` approach). Two alternative approaches and one upgrade are documented below.

### Current approach: injected dev environment (`nix print-dev-env`)

`nix print-dev-env` (Nix ≥ 2.4) evaluates a flake's `devShell` on the host and writes a shell script (`dev-env.sh`) that sets `PATH`, `CC`, `PKG_CONFIG_PATH`, etc. to the relevant `/nix/store/...` paths. Since the store is read-only mounted, those paths are accessible without a daemon socket.

- `gen-dev-env.sh` runs `nix print-dev-env` and writes `dev-env.sh` into the project directory (its second argument), independent of where the flake lives.
- `exec.sh` sources `dev-env.sh` inside the container via `bash -c "source /work/POD_NAME/dev-env.sh && cd /work/POD_NAME && exec bash -i"`.
- Re-run `gen-dev-env.sh` whenever the flake's inputs change.
- Only works for packages already in the host store; run `nix develop` on the host first if the flake has new deps.

### Option A: Socket at a non-standard path (defense by friction)

Mount the daemon socket at a non-standard container path (e.g. `/run/host-nix.sock`) instead of the default `/nix/var/nix/daemon-socket/`. Nix tools won't find it by default and fall back to local mode (which fails because `/nix/store` is read-only), so all Nix operations fail silently unless the user explicitly sets `NIX_REMOTE`:

```bash
NIX_REMOTE=unix:///run/host-nix.sock nix develop
```

Destructive commands require the same flag — friction, not isolation. In `claude-env.yaml`:

```yaml
volumeMounts:
  - name: nix-daemon-socket
    mountPath: /run/host-nix.sock
```

Composable with the current approach: no socket by default, socket available at a known path as an escape hatch.

### Option B: Container-owned Nix store with host daemon as substituter

The strongest isolation. The container gets its own writable `/nix` Podman volume and a local Nix daemon; the host daemon socket is mounted read-only at a non-standard path purely as a binary cache.

1. **Container `/nix` volume** — a named Podman volume, completely independent of the host store.
2. **Container-local Nix daemon** — add `pkgs.nix` to the image; run `nix-daemon &` at startup via an entrypoint script.
3. **Host socket at `/run/host-nix.sock`** — read-only bind mount; never the default daemon.
4. **`daemon://` substituter** — in the container's `/etc/nix/nix.conf`:
   ```
   extra-substituters = daemon:///run/host-nix.sock
   ```
   The container daemon fetches pre-built NARs from the host on cache miss; most derivations are already present, so network traffic is minimal.

**Trade-offs:**

| | Current (`print-dev-env`) | Option A (non-standard socket) | Option B (container store) |
|---|---|---|---|
| Setup complexity | `gen-dev-env.sh` step | Minimal YAML change | Entrypoint script + `nix-daemon` in image |
| Host store isolation | Complete (no socket) | Friction only | Complete |
| Disk usage | Zero extra | Zero extra | Duplicates container builds |
| `nix develop` inside container | No (env injected externally) | With `NIX_REMOTE=` | Yes |
| Host socket exposure | None | Non-default path | Read-only, non-default path |

Option B is not currently implemented but is the natural next step if full store isolation with in-container `nix develop` is required.

## Dev shell (flake)

Enter the dev shell for working on this repo:

```bash
nix develop
```

Update pinned inputs:

```bash
nix flake update
```
