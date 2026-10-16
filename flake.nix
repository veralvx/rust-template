# This repository's flake -- the template's, not a generated project's (template/flake.nix is that):
# the tools its maintainers run, and the checks that need no network.
#
#   nix develop      the shell: cargo-generate, just, shellcheck, shfmt, actionlint, dprint, cog,
#                    git-cliff, nixfmt, Python for render-check
#   nix fmt          the formatter: nixfmt, shfmt (as .editorconfig says) and just's own, through
#                    treefmt; `nix fmt -- --ci` (`just nix`) formats, and fails if that changed a
#                    file
#   nix flake check  the format (the formatter's verdict), the shell (`just shell-check`, here and
#                    in template/) and the workflows (actionlint), offline in the sandbox
#
# A generated project's tools are its own flake's (template/flake.nix); `just smoke` runs its
# checks in that flake's shell.
{
  description = "rust-template: the development shell and checks of a cargo-generate template";

  # the unstable channel: cargo-generate 0.25, which the template asks for, is there
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      # nixpkgs-unstable's platforms: it dropped x86_64-darwin in 26.11
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        pkgs:
        let
          justFmt = [
            "--fmt"
            "--unstable"
            "--justfile"
          ];
          # `nix fmt`: each tool on its own files -- the shell scripts by extension, the hooks (here
          # and the template's) by their directory, as they have none; each justfile by name, as
          # `just --fmt` takes one at a time. template/flake.nix holds Liquid, which no Nix parser
          # reads: the generated project's formatter checks it, rendered.
          formatter = pkgs.treefmt.withConfig {
            settings = {
              on-unmatched = "info";
              formatter = {
                nixfmt = {
                  command = "nixfmt";
                  includes = [ "*.nix" ];
                  excludes = [ "template/flake.nix" ];
                };
                shfmt = {
                  command = "shfmt";
                  options = [ "--write" ];
                  includes = [
                    "*.sh"
                    ".githooks/*"
                    "template/.githooks/*"
                  ];
                };
                just = {
                  command = "just";
                  options = justFmt;
                  includes = [ "justfile" ];
                };
                just-template = {
                  command = "just";
                  options = justFmt;
                  includes = [ "template/justfile" ];
                };
              };
            };
            runtimeInputs = [
              pkgs.nixfmt
              pkgs.shfmt
              pkgs.just
            ];
          };
          # a check on a writable copy, in a repository of its own: the recipes list git's files.
          # The sandbox has no /usr/bin/env, which the justfiles' script recipes name: their bash
          # is named by its path instead (to `just shell-check`, the same shell either way).
          onCopy =
            name: nativeBuildInputs: script:
            pkgs.runCommand name { inherit nativeBuildInputs; } ''
              cp -r ${./.} "$TMPDIR/repository"
              chmod -R u+w "$TMPDIR/repository"
              cd "$TMPDIR/repository"
              export HOME="$TMPDIR"
              substituteInPlace justfile template/justfile \
                --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
              git init --quiet
              git add --all
              ${script}
              touch $out
            '';
          shellTools = [
            pkgs.just
            pkgs.jq
            pkgs.gitMinimal
            pkgs.shellcheck
            pkgs.shfmt
          ];
        in
        {
          checks = {
            # the formatter's verdict on the whole tree: what `nix fmt` would change fails it
            format = formatter.check ./.;
            shell = onCopy "shell" shellTools "just shell-check template-shell-check";
            workflows = onCopy "workflows" (shellTools ++ [ pkgs.actionlint ]) "just actionlint";
          };

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.cargo-generate
              pkgs.just
              pkgs.jq
              pkgs.shellcheck
              pkgs.shfmt
              pkgs.actionlint
              pkgs.dprint
              pkgs.cocogitto
              pkgs.git-cliff
              pkgs.nixfmt
              # render-check's: it installs python-liquid, which nixpkgs lacks, into .venv
              pkgs.python3
            ];
          };

          inherit formatter;
        };

      bySystem = lib.genAttrs systems (system: perSystem nixpkgs.legacyPackages.${system});
      output = name: lib.mapAttrs (_: outputs: outputs.${name}) bySystem;
    in
    {
      checks = output "checks";
      devShells = output "devShells";
      formatter = output "formatter";
    };
}
