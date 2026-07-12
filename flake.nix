{
  description = "Secure Podman environment for Claude Code";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # UID/GID 0 in a rootless container maps to the host user (bbush) on disk.
        uid = 0;
        gid = 0;

        containerEnv = pkgs.buildEnv {
          name  = "claude-env";
          paths = with pkgs; [
            # Claude Code and shell
            claude-code bashInteractive coreutils cacert
            # VCS
            git gh
            # Shell utilities not in coreutils
            findutils gnugrep gnused gawk diffutils patch less which procps file
            # Network and data
            curl jq ripgrep
            # Scripting
            gnumake
            python3
            # Diagnostics
            strace
            # UI
            neovim
          ];
        };

        container = pkgs.dockerTools.buildLayeredImage {
          name = "claude-env";
          tag  = "latest";

          contents = [
            containerEnv
            (pkgs.writeTextDir "etc/passwd"
              "root:x:0:0:root:/root:/bin/sh\nclaude:x:${toString uid}:${toString gid}::/home/claude:${pkgs.bashInteractive}/bin/bash\n")
            (pkgs.writeTextDir "etc/group"
              "root:x:0:\nclaude:x:${toString gid}:\n")
            # Placeholder mount targets — Podman bind-mounts the real content over these at startup.
            (pkgs.writeTextDir "etc/resolv.conf" "")
            (pkgs.writeTextDir "etc/hosts"       "")
            (pkgs.writeTextDir "etc/hostname"    "")
          ];

          extraCommands = ''
            mkdir -p home/claude/.claude
          '';

          config = {
            User       = "0";
            WorkingDir = "/home/claude";
            Env        = [
              "HOME=/home/claude"
              # /bin from containerEnv; Nix paths from host-mounted /nix.
              # system/sw/bin covers NixOS; default/bin covers standalone Nix installs.
              "PATH=/nix/var/nix/profiles/system/sw/bin:/nix/var/nix/profiles/default/bin:/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            Cmd        = [ "/bin/sleep" "infinity" ];
            Volumes    = {
              "/home/claude" = {};
            };
          };
        };

      in {

        # Linux-only; `nix build .` builds the container image.
        packages = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          inherit container;
          default = container;
        };

        apps.default = flake-utils.lib.mkApp { drv = pkgs.claude-code; };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ claude-code gh ];
          shellHook = ''
            PS1=$(printf '\n\001\033[1;32m\002[nix develop:\\w]\\$\001\033[0m\002 ')
            export PS1
          '';
        };
      }
    );
}
