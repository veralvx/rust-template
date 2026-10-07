# {{project-name}}

{{description}}

## First steps

`cargo-generate` initialises a git repository here but does not commit
anything, so the first commit is yours to make — and `cog check` (run by
`just checks` and by CI) requires it to follow
[Conventional Commits](https://www.conventionalcommits.org/):

```sh
git add .
git commit -m "chore: initial commit from template"
```

With [Nix](https://nixos.org), `nix develop` enters a shell with the pinned
toolchain and every tool below; its first run writes `flake.lock` -- commit it
too.

Then, in whichever order suits you:

- Push to `https://github.com/{{github_username}}/{{project-name}}`.
- Enable the repository settings the auto-merge workflow needs — they are listed
  at the top of `.github/workflows/dependabot-automerge.yml`. Without required
  status checks, it merges bumps that CI never gated.
- Enable private vulnerability reporting (Settings → Code security): it is off
  by default, and [SECURITY.md](SECURITY.md) and the issue form point to it.
{% if project_kind != "lib" -%}
- Run `dist init` to generate `.github/workflows/release.yml` from
  `dist-workspace.toml`, and commit it.
{% endif -%}
- Run `just checks` once to confirm your toolchain is complete: a step that
  stops on a missing command names it -- `just`, `jq`, `dprint`, `cog`,
  `cargo-audit` or the nightly Miri component ([CONTRIBUTING.md](CONTRIBUTING.md)
  lists them; `nix develop` has them all).
- Read [AGENTS.md](AGENTS.md) before writing code: the lint policy denies
  `unwrap`, `panic!`, indexing, unchecked arithmetic and `as` casts, and it is
  much less surprising if you know that going in.

## Requirements

- Rust {{msrv}} or later (pinned in `rust-toolchain.toml`), or Nix: `nix develop`
  provides that toolchain{% if project_kind != "lib" %}, and `nix build` the binary{% endif %}.

## Install
{% if project_kind == "lib" %}
```sh
cargo add {{project-name}}
```
{% else %}
```sh
cargo install {{project-name}}
```

Or, with [`cargo-binstall`](https://github.com/cargo-bins/cargo-binstall), to
fetch a prebuilt binary from the GitHub release `dist` builds, instead of
compiling:

```sh
cargo binstall {{project-name}}
```
{% endif %}
## Build from source

```sh
git clone https://github.com/{{github_username}}/{{project-name}}.git
cd {{project-name}}
cargo build --release
```

## Usage
{% if project_kind == "lib" %}
```rust
use {{crate_name}}::saturating_total;

assert_eq!(saturating_total(2, 3), 5);
```
{% elsif project_kind == "workspace" %}
```sh
{{project-name}}
```

The logic lives in `crates/{{project-name}}-core`, which is usable on its own:

```rust
use {{crate_name}}_core::saturating_total;

assert_eq!(saturating_total(2, 3), 5);
```
{% else %}
```sh
{{project-name}}
```
{% endif %}
{% if project_kind == "workspace" -%}
## Layout

```
Cargo.toml                      workspace root: shared metadata, lint policy, profiles
crates/{{project-name}}/           the binary -- argument handling only
crates/{{project-name}}-core/      the library -- everything worth testing
```

The lint policy is declared once at the root under `[workspace.lints]`; each
member inherits it with `[lints] workspace = true`. Add a member by creating
`crates/<name>/`, listing it in the root `members`, and giving it that same two
line `[lints]` table -- a member that omits it silently opts out of the policy --
and copies of the licence files, since its `.crate` holds its own directory
only.

{% endif -%}
## Development

This repository uses [`just`](https://github.com/casey/just) to mirror CI
locally. `just checks` runs the nine checks the workflows run, on the toolchain
`rust-toolchain.toml` pins (CI also runs clippy and rustdoc on the latest
stable, where a newer lint can still fire):

```sh
just checks
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the toolchain those checks need and
how a release is cut, and [AGENTS.md](AGENTS.md) for the lint policy and what to
do when a lint fires.

## License
{% if license == "MIT OR Apache-2.0" %}
Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  <http://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or
  <http://opensource.org/licenses/MIT>)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.
{%- elsif license == "MIT" %}
Licensed under the MIT license ([LICENSE-MIT](LICENSE-MIT) or
<http://opensource.org/licenses/MIT>).
{%- else %}
Licensed under the Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE)
or <http://www.apache.org/licenses/LICENSE-2.0>).
{%- endif %}
