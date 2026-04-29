{
  description = "Environment for Claude Code";

  inputs = {
    nixpkgs.url = "github:Nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };


      in
      {
        apps.default = flake-utils.lib.mkApp { drv = pkgs.claude-code; };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            claude-code
            gh
          ];

          shellHook = ''
            export PS1="\n\[\033[1;32m\][nix develop:\w]\$\[\033[0m\] "
          '';
        };
      }
    );
}
