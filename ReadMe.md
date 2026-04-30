# claude-env

A secure Podman container for running Claude Code against a Nix-managed project.

## One-time setup

```bash
# 1. Copy your Claude Code credentials into the container home.
mkdir -p claude/.claude
cp ~/.claude/.credentials.json claude/.claude/.credentials.json

# 2. Build and load the container image.
nix build
podman load < result
```

## Workflow

**Before starting the container** (or whenever the project's flake inputs change), generate the dev environment script on the host:

```bash
./gen-dev-env.sh examples/rust   # writes examples/rust/dev-env.sh
./gen-dev-env.sh /path/to/project
```

**Start the pod,** passing the project directory (pod name defaults to the last path component):

```bash
./play.sh examples/rust              # pod named "rust"
./play.sh /path/to/project           # pod named "project"
./play.sh /path/to/project mypod     # explicit pod name
```

The pod name must be unique if running multiple pods simultaneously. The project directory is mounted as `/work` inside the container.

**Enter the container** (pod name matches the last component of the work directory):

```bash
./exec.sh rust
```

This sources `/work/dev-env.sh`, changes to `/work`, and drops you into an interactive shell with the project's dev environment (PATH, CC, PS1, etc.) already set. Start Claude Code with `claude`.

**Tear down:**

```bash
podman pod stop rust && podman pod rm rust
```

## Running multiple pods simultaneously

Each pod has its own name, its own `/work` mount, and its own `dev-env.sh` (stored in the project directory). There is no shared mutable state between pods.

```bash
./gen-dev-env.sh examples/rust    && ./play.sh examples/rust    && ./exec.sh rust
./gen-dev-env.sh examples/haskell && ./play.sh examples/haskell && ./exec.sh haskell
```

## How it works

`nix print-dev-env` evaluates the project flake's `devShell` on the host and emits a shell script that sets `PATH` and build variables to the relevant `/nix/store/...` paths. Since the container mounts the host Nix store read-only, those paths are accessible without a daemon socket. The container has no write access to the Nix store and no daemon socket — it can read derivations but cannot build, delete, or garbage-collect them.

See `CLAUDE.md` for architecture details and alternative approaches.
