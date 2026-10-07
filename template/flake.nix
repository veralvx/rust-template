# {{project-name}}'s flake: the toolchain rust-toolchain.toml pins -- rust-overlay reads that
# file, so the MSRV is written once and rustup and Nix build with the same compiler -- the
# tools `just checks` and `just release` run, and CI's checks as derivations.
#
#   nix develop          the shell: the toolchain, just, dprint, cog, git-cliff, cargo-audit...
#   nix develop .#miri   nightly with Miri (`just miri` enters it on its own)
#   nix flake check      clippy, rustfmt, rustdoc and the tests, offline in the sandbox
{%- if project_kind != "lib" %}
#   nix build            the binary, as ./result/bin/{{project-name}}
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

      # name, version and description from the manifests, so a release's bump is the flake's
      manifest = lib.importTOML ./Cargo.toml;
{%- if project_kind == "workspace" %}
      inherit (manifest.workspace.package) version;
      cargoPackage = (lib.importTOML ./crates/{{project-name}}/Cargo.toml).package;
{%- else %}
      inherit (manifest.package) version;
      cargoPackage = manifest.package;
{%- endif %}
      pname = cargoPackage.name;

      # what a build reads: nothing else reaches the store, so editing the docs or CI
      # rebuilds nothing
      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./Cargo.toml
          ./Cargo.lock
          ./clippy.toml
          ./rustfmt.toml
{%- if project_kind == "workspace" %}
          ./crates
{%- else %}
          ./src
{%- endif %}
{%- if project_kind == "lib" or project_kind == "both" %}
          ./tests
{%- endif %}
        ];
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
                installPhase = "touch $out";
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
                mainProgram = pname;
              };
            }
          );
{%- endif %}
        in
        {
{%- if project_kind != "lib" %}
          packages.default = package;
{%- endif %}
          checks = {
            clippy = cargoCheck "clippy" "cargo clippy --workspace --all-targets --all-features --locked --offline -- -D warnings";
            fmt = cargoCheck "fmt" "cargo fmt --all -- --check";
            doc = cargoCheck "doc" "RUSTDOCFLAGS='-D warnings' cargo doc --workspace --no-deps --all-features --locked --offline";
{%- if project_kind == "lib" %}
            tests = cargoCheck "tests" "cargo test --workspace --all-targets --all-features --locked --offline && cargo test --workspace --doc --all-features --locked --offline";
{%- else %}
            inherit package;
{%- endif %}
          };
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
          formatter = pkgs.nixfmt;
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
