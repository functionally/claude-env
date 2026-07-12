# claude-env

A secure Podman container for running Claude Code against a Nix-managed project.

Each project is mounted at its own path inside the container, and the flake that
provides the dev environment can live anywhere — so one shared flake can serve
many projects, and each project keeps its own isolated Claude Code session
history within a single shared home.

## One-time setup

```bash
# 1. Copy your Claude Code credentials into the container home.
mkdir -p claude/.claude
cp ~/.claude/.credentials.json claude/.claude/.credentials.json

# 2. Build and load the container image.
nix build
podman load < result
```

Your account credentials and any global settings (status line, etc.) live in
`claude/.claude/` and are shared across every pod started from this clone. To keep
a work account and a personal account separate, clone this repository twice and
copy the appropriate credentials into each clone's `claude/.claude/`.

## Workflow

**1. Generate the dev environment** (whenever the flake's inputs change). This now
takes two arguments — the flake and the project directory — so the flake need not
live inside the project:

```bash
# gen-dev-env.sh FLAKE_PATH PROJECT_DIR
./gen-dev-env.sh examples/rust examples/rust          # flake and project coincide
./gen-dev-env.sh /path/to/shared-flake /path/to/proj  # one shared flake, any project
```

`dev-env.sh` is written into `PROJECT_DIR`, so it appears inside the container at
`/work/POD_NAME/dev-env.sh` and is sourced automatically by `exec.sh`.

**2. Start the pod,** passing the project directory (pod name defaults to the last
path component):

```bash
./play.sh examples/rust              # pod named "rust"
./play.sh /path/to/project           # pod named "project"
./play.sh /path/to/project mypod     # explicit pod name
```

The pod name must be unique if running multiple pods simultaneously. The project
directory is mounted at `/work/POD_NAME` inside the container (not bare `/work`),
which gives each project a distinct path — and therefore a distinct Claude Code
session slug.

**3. Enter the container** (pod name matches the last component of the work
directory unless you set one explicitly):

```bash
./exec.sh rust
```

This sources `/work/rust/dev-env.sh`, changes to `/work/rust`, and drops you into
an interactive shell with the project's dev environment (PATH, CC, PS1, etc.)
already set. Start Claude Code with `claude`.

> **Launch `claude` from `/work/POD_NAME`, not a subdirectory.** Claude Code keys
> its session history to the directory it is launched from. `exec.sh` puts you in
> the right place; if you `cd` into a subfolder first and then run `claude`, that
> subfolder becomes a separate session bucket and `claude --resume` will not find
> the sessions you expect. If you routinely work from a nested root, mount that
> nested directory as the project (pass it as the `play.sh` argument) so it
> becomes `/work/POD_NAME` directly.

**4. Tear down:**

```bash
podman pod stop rust && podman pod rm rust
```

## Sessions: shared store, isolated resume

All session history lives in the one shared home at
`claude/.claude/projects/`, so every project's transcripts sit in a single place
you can browse or back up together. Because each project is mounted at a distinct
`/work/POD_NAME`, Claude Code files its sessions under a distinct slug per project.
The practical effect:

- `claude --resume` launched from `/work/POD_NAME` only lists **that** project's
  sessions.
- One project's Claude session never reads another project's session files.
- The transcripts themselves all reside in the shared home, not scattered across
  the project directories.

The project's *files* remain isolated by the mount — a pod can only see its own
`/work/POD_NAME`, never another project's directory.

## Running multiple pods simultaneously

Each pod has its own name, its own `/work/POD_NAME` mount, and its own
`dev-env.sh` (stored in the project directory). Project files are isolated by the
mount; session history is shared in one home but scoped per project on resume.

```bash
./gen-dev-env.sh /path/to/shared-flake examples/rust    && ./play.sh examples/rust    && ./exec.sh rust
./gen-dev-env.sh /path/to/shared-flake examples/haskell && ./play.sh examples/haskell && ./exec.sh haskell
```

## Note on `dev-env.sh` in project directories

`gen-dev-env.sh` writes `dev-env.sh` into each project directory. If a project is
a git repository, add `dev-env.sh` to its `.gitignore` (and `.claude/` if you do
not want project-local Claude settings or session-adjacent files tracked).

## How it works

`nix print-dev-env` evaluates a flake's `devShell` on the host and emits a shell
script that sets `PATH` and build variables to the relevant `/nix/store/...`
paths. Since the container mounts the host Nix store read-only, those paths are
accessible without a daemon socket. The container has no write access to the Nix
store and no daemon socket — it can read derivations but cannot build, delete, or
garbage-collect them. Because the emitted paths are absolute `/nix/store` paths,
the flake that produced them does not need to be visible inside the container at
all — only the store does.

See `CLAUDE.md` for architecture details and alternative approaches.
