# {{project-name}}'s flake: the toolchain rust-toolchain.toml pins -- rust-overlay reads that
# file, so the MSRV is written once and rustup and Nix build with the same compiler -- the
# tools `just checks` and `just release` run, and CI's checks as derivations.
#
#   nix develop          the shell: the toolchain, just, dprint, cog, git-cliff, cargo-audit...
#   nix develop .#miri   nightly with Miri (`just miri` enters it on its own)
#   nix fmt              nixfmt, shfmt (as .editorconfig says) and just's own, through
#                        treefmt; `nix fmt -- --ci` (`just nix`) formats, and fails if that
#                        changed a file
#   nix flake check      clippy, rustfmt, rustdoc and the tests, the format (`nix fmt`'s
#                        verdict), the shell (`just shell-check`) and the workflows
#                        (actionlint), offline in the sandbox
{%- if project_kind != "lib" %}
#   nix build            the binary, as ./result/bin/{{project-name}}
{%- endif %}
{%- if project_kind != "lib" and container_image %}
#   nix build .#image    the binary as an OCI image (Linux): a gzipped docker-archive
{%- endif %}
#
# The first nix command writes flake.lock: commit it; `nix flake update` moves it.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, rust-overlay, ... }:
    let
      inherit (nixpkgs) lib;
      # nixpkgs-unstable's platforms: it dropped x86_64-darwin in 26.11
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # name, version, description, licence and repository from the manifests, so a release's
      # bump is the flake's
      manifest = lib.importTOML ./Cargo.toml;
{%- if project_kind == "workspace" %}
      inherit (manifest.workspace.package) version license repository;
      cargoPackage = (lib.importTOML ./crates/{{project-name}}/Cargo.toml).package;
{%- else %}
      inherit (manifest.package) version license repository;
      cargoPackage = manifest.package;
{%- endif %}
      pname = cargoPackage.name;

      # what a build reads: the repository less its tooling and contributor docs, so editing
      # those rebuilds nothing, while a new build.rs, examples/ or benches/ is in without a
      # word; README.md and the licences stay, for a crate that `include_str!`s them
      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.difference ./. (
          lib.fileset.unions (
            map lib.fileset.maybeMissing [
              ./.githooks
              ./.github
              ./.gitignore
              ./AGENTS.md
              ./CHANGELOG.md
              ./CODE_OF_CONDUCT.md
              ./CONTRIBUTING.md
              ./SECURITY.md
              ./cliff.toml
              ./cog.toml
              ./dist-workspace.toml
              ./dprint.json
              ./flake.lock
              ./flake.nix
              ./justfile
            ]
          )
        );
      };

      perSystem =
        pkgs:
        let
          rust-bin = rust-overlay.lib.mkRustBin { } pkgs;
          toolchain = rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          rustPlatform = pkgs.makeRustPlatform {
            cargo = toolchain;
            rustc = toolchain;
          };
          # `nix fmt`: each tool on its own files -- the shell scripts by extension, the hooks by
          # their directory, as they have none, the justfile by name, as `just --fmt` takes one.
          # The Rust is rustfmt's (`just fmt`).
          formatter = pkgs.treefmt.withConfig {
            settings = {
              on-unmatched = "info";
              formatter = {
                nixfmt = {
                  command = "nixfmt";
                  includes = [ "*.nix" ];
                };
                shfmt = {
                  command = "shfmt";
                  options = [ "--write" ];
                  includes = [
                    "*.sh"
                    ".githooks/*"
                  ];
                };
                just = {
                  command = "just";
                  options = [
                    "--fmt"
                    "--unstable"
                    "--justfile"
                  ];
                  includes = [ "justfile" ];
                };
              };
            };
            runtimeInputs = [
              pkgs.nixfmt
              pkgs.shfmt
              pkgs.just
            ];
          };
          common = {
            inherit version src;
            cargoLock.lockFile = ./Cargo.lock;
          };
          # a check: one cargo command, offline against the vendored lock, a stamp for output
          cargoCheck =
            name: command:
            rustPlatform.buildRustPackage (
              common
              // {
                pname = "${pname}-${name}";
                buildPhase = ''
                  runHook preBuild
                  ${command}
                  runHook postBuild
                '';
                doCheck = false;
                installPhase = ''
                  runHook preInstall
                  touch $out
                  runHook postInstall
                '';
              }
            );
{%- if project_kind != "lib" %}
          # the release build, its tests run by buildRustPackage's checkPhase
          package = rustPlatform.buildRustPackage (
            common
            // {
              inherit pname;
{%- if project_kind == "workspace" %}
              cargoBuildFlags = [ "--package=${pname}" ];
              cargoTestFlags = [ "--workspace" ];
{%- endif %}
              meta = {
                inherit (cargoPackage) description;
                homepage = repository;
                # the SPDX expression's licence identifiers: its operators, parentheses and
                # `WITH` exceptions aside
                license = map lib.getLicenseFromSpdxId (
                  lib.subtractLists [ "" "AND" "OR" ] (
                    lib.filter lib.isString (builtins.split "[ ()]+|WITH [^ ()]+" license)
                  )
                );
                mainProgram = pname;
              };
            }
          );
{%- endif %}
{%- if project_kind != "lib" and container_image %}
          # the binary as an OCI image: its closure alone -- no base image, no /bin/sh -- run as
          # nobody. `.#image.stream` streams the archive uncompressed (image.yml's: no second
          # copy of the closure in the store)
          image = pkgs.dockerTools.buildLayeredImage {
            name = pname;
            tag = version;
            # std::env::temp_dir's default; the image has no other
            extraCommands = "mkdir -m 1777 tmp";
            config = {
              Entrypoint = [ (lib.getExe package) ];
              # nobody: nothing in it needs root, and a numeric user needs no /etc/passwd
              User = "65534:65534";
              # what GHCR reads (docs.github.com, "Working with the Container registry"): the
              # source links the image to its repository
              Labels = {
                "org.opencontainers.image.title" = pname;
                "org.opencontainers.image.description" = cargoPackage.description;
                "org.opencontainers.image.version" = version;
                "org.opencontainers.image.source" = repository;
                "org.opencontainers.image.licenses" = license;
              };
            };
          };
          # Linux's alone: an image's binary is Linux's
          linux = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux { inherit image; };
{%- endif %}
        in
        {
{%- if project_kind != "lib" and container_image %}
          packages = {
            default = package;
          }
          // linux;
{%- elsif project_kind != "lib" %}
          packages.default = package;
{%- endif %}
          checks = {
            clippy = cargoCheck "clippy" "cargo clippy --workspace --all-targets --all-features --locked --offline -- -D warnings";
            fmt = cargoCheck "fmt" "cargo fmt --all -- --check";
            doc = cargoCheck "doc" "RUSTDOCFLAGS='-D warnings' cargo doc --workspace --no-deps --all-features --locked --offline";
            # the formatter's verdict on the whole tree: what `nix fmt` would change fails it
            format = formatter.check ./.;
            # `just shell-check` on a copy, in a repository of its own: it lists the scripts git
            # does not ignore. The sandbox has no /usr/bin/env, which the script recipes name:
            # their bash is named by its path instead (to `just shell-check`, the same shell
            # either way).
            shell =
              pkgs.runCommand "shell"
                {
                  nativeBuildInputs = [
                    pkgs.just
                    pkgs.jq
                    pkgs.gitMinimal
                    pkgs.shellcheck
                    pkgs.shfmt
                  ];
                }
                ''
                  cp -r ${./.} "$TMPDIR/project"
                  chmod -R u+w "$TMPDIR/project"
                  cd "$TMPDIR/project"
                  export HOME="$TMPDIR"
                  substituteInPlace justfile \
                    --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
                  git init --quiet
                  git add --all
                  just shell-check
                  touch $out
                '';
            # actionlint on a copy, in a repository of its own, as `just actionlint` runs it: with
            # no file named, actionlint finds the workflows, and .github/actionlint.yaml if there is
            # one, from the repository's root
            workflows =
              pkgs.runCommand "workflows"
                {
                  nativeBuildInputs = [
                    pkgs.actionlint
                    pkgs.shellcheck
                    pkgs.gitMinimal
                  ];
                }
                ''
                  cp -r ${./.} "$TMPDIR/project"
                  chmod -R u+w "$TMPDIR/project"
                  cd "$TMPDIR/project"
                  export HOME="$TMPDIR"
                  git init --quiet
                  actionlint
                  touch $out
                '';
{%- if project_kind == "lib" %}
            tests = cargoCheck "tests" "cargo test --workspace --all-targets --all-features --locked --offline && cargo test --workspace --doc --all-features --locked --offline";
{%- else %}
            inherit package;
{%- endif %}
          }
{%- if project_kind != "lib" and container_image %}
          # the image built: its layers, from the binary's closure
          // linux
{%- endif %};
          devShells = {
            default = pkgs.mkShell {
              packages = [
                toolchain
                pkgs.just
                pkgs.jq
                pkgs.dprint
                pkgs.cocogitto
                pkgs.git-cliff
                pkgs.cargo-audit
                pkgs.shellcheck
                pkgs.shfmt
                pkgs.actionlint
{%- if project_kind != "lib" %}
                pkgs.cargo-dist
{%- endif %}
                pkgs.nixfmt
              ]
              ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.valgrind ];
            };
            # Miri runs on nightly only: rust-overlay's latest nightly that ships it
            miri = pkgs.mkShell {
              packages = [
                (rust-bin.selectLatestNightlyWith (
                  nightly:
                  nightly.minimal.override {
                    extensions = [
                      "miri"
                      "rust-src"
                    ];
                  }
                ))
              ];
            };
          };
          inherit formatter;
        };

      bySystem = lib.genAttrs systems (system: perSystem nixpkgs.legacyPackages.${system});
      output = name: lib.mapAttrs (_: outputs: outputs.${name}) bySystem;
    in
    {
{%- if project_kind != "lib" %}
      packages = output "packages";
{%- endif %}
      checks = output "checks";
      devShells = output "devShells";
      formatter = output "formatter";
    };
}
