# rust-template

A [`cargo-generate`](https://github.com/cargo-generate/cargo-generate) template
for a Rust crate that starts out with the whole toolchain already wired up:
a deliberately strict lint policy, GitHub Actions CI, Conventional Commits,
changelog generation, dependency auditing, a Nix flake, and a `justfile` that
runs the same checks locally that CI runs remotely.

The configuration is adapted from [`veralvx/imi`](https://github.com/veralvx/imi)
(MIT OR Apache-2.0). See [Attribution](#attribution).

## Usage

```sh
cargo install cargo-generate
cargo generate --git https://github.com/veralvx/rust-template template
```

The trailing `template` is the sub-folder that holds the template itself; the
repository root holds this README and the template's own CI. `cargo-generate`
will find it on its own if you omit the argument, but naming it is unambiguous.

From a local checkout:

```sh
cargo generate --path ./rust-template template
```

Everything can be answered non-interactively, which is what the smoke test does:

```sh
cargo generate --path ./rust-template template \
  --name my-crate --silent \
  -d description="Does a thing." \
  -d project_kind=both \
  -d author_name="Jane Doe" \
  -d author_email=jane@example.com \
  -d github_username=jane \
  -d license="MIT OR Apache-2.0" \
  -d msrv=1.97 \
  -d keywords="cli,parser" \
  -d categories="command-line-utilities"
```

### If generation fails

`cargo-generate` creates the destination directory *before* it validates any
answer, and leaves it behind when validation rejects one. The retry then stops
with `Target directory already exists, aborting!`, which reads as though the
first run succeeded. It did not — remove the empty directory and try again:

```sh
rm -rf ./my-crate && cargo generate --git ... template --name my-crate
```

This template validates nine answers, so it runs into this more often than a
template that validates none.

## What you are asked

| Prompt            | Default             | Goes into                                                          |
| ----------------- | ------------------- | ------------------------------------------------------------------ |
| *(project name)*  | —                   | package name, `[[bin]]`, repository URL, docs                       |
| `description`     | `A Rust crate.`     | `package.description`, README, the flake's `meta`                   |
| `project_kind`    | `bin`               | `bin`, `lib`, `both`, or `workspace` — see below                    |
| `author_name`     | —                   | `package.authors`, license copyright line                           |
| `author_email`    | *(empty)*           | `package.authors`, code of conduct — omitted if blank               |
| `github_username` | —                   | repository URL, security advisory link                              |
| `license`         | `MIT OR Apache-2.0` | `package.license`, which `LICENSE-*` files are kept, README         |
| `msrv`            | `1.97`              | `package.rust-version`, `rust-toolchain.toml`, CI's MSRV job, Nix   |
| `keywords`        | `rust`              | `package.keywords` (comma-separated, max 5)                         |
| `categories`      | `development-tools` | `package.categories` (comma-separated, max 5)                       |

Every answer is validated by a regex at the prompt, so a typo is caught before
generation rather than at `cargo publish`. `description` and `author_name`
land in TOML strings, so they may not hold `"` or `\`. `keywords` and
`categories` follow crates.io's rules (max 5 each, 20 characters per keyword),
and neither may be empty: `clippy::cargo_common_metadata` is enabled and
requires both.

### What `project_kind` selects

| Value       | Layout                                                                 |
| ----------- | ---------------------------------------------------------------------- |
| `bin`       | one package, `src/main.rs`                                              |
| `lib`       | one package, `src/lib.rs` + `tests/`                                    |
| `both`      | one package with both targets; the binary calls into its own library    |
| `workspace` | `crates/<name>` (binary) + `crates/<name>-core` (library), two packages |

`workspace` mirrors the reference project's shape. The root manifest holds
`[workspace.package]`, `[workspace.dependencies]`, the profiles, and the lint
policy under `[workspace.lints]`; each member inherits the policy with
`[lints] workspace = true`. `description` and `categories` stay per member,
because crates.io shows them per package.

Nothing else changes: every CI command and every `just` recipe already passes
`--workspace`, so the same nine checks cover one package or five.

Three things worth knowing if you pick it:

- `cargo publish --workspace` publishes members in dependency order. `just
  release` bumps the root version *and* the version on any dependency line that
  also carries a `path =` — those are the intra-workspace ones, and a stale one
  makes publishing fail.
- A new member that omits `[lints] workspace = true` silently opts out of the
  entire lint policy. There is no warning for it; it is the one footgun the
  workspace layout adds.
- A member's `.crate` holds its own directory only, so each member carries
  copies of the licence texts; a new member needs them too.

### Why the MSRV prompt behaves the way it does

The hard floor is **1.90**. Edition 2024 alone would allow 1.85, but `just
release` publishes with `cargo publish --workspace`, which cargo stabilised in
1.90 -- and `rust-toolchain.toml` pins cargo to the MSRV, so an older MSRV would
leave a project unable to release. The default is **1.97**, which is the
version at which every lint name in the manifest exists.

Three of the names are newer than 1.90: `clippy::unchecked_time_subtraction`
arrived in 1.92 (renamed from `unchecked_duration_subtraction`), and
`clippy::inline_trait_bounds` and `clippy::inline_modules` arrived in 1.97.

Choosing an MSRV between 1.90 and 1.96 is supported. The consequence is narrow:

- `cargo check` and `cargo test` are **completely silent** -- rustc ignores
  `clippy::` names it does not recognise, so an older MSRV job sees nothing.
- `cargo clippy` prints `warning[E0602]: unknown lint` for each name it does not
  know and **exits 0**, so it fails no build, including under `-D warnings`.
- You only see those warnings locally, because `rust-toolchain.toml` pins your
  toolchain to the MSRV. The CI clippy job runs on stable, where all three
  names exist.

That behaviour was measured on rustc 1.85.1 with clippy 0.1.85, when 1.85 was
the floor; the floor's toolchain itself has not been re-run since it moved to
1.90 (see [Verification status](#verification-status)).

## What you get

```
Cargo.toml            strict lint policy, release profile, crates.io metadata
Cargo.lock            committed, so CI's --locked builds work from commit one
clippy.toml           test code exempted from the panic-family lints
rust-toolchain.toml   pinned to the MSRV
rustfmt.toml          edition 2024, 100 columns
dprint.json           Markdown + TOML formatting, plugins at their latest
cliff.toml            git-cliff changelog generation, grouped by commit type
cog.toml              cocogitto / Conventional Commits
dist-workspace.toml   cargo-dist config (binaries only)
justfile              `just checks` = the nine checks CI runs; `just release`
.githooks/            opt-in (`just install-hooks`): formatting before a
                      commit, Conventional Commits for the message and the push
flake.nix             Nix: the pinned toolchain and every tool, the package,
                      CI's checks as derivations
.cargo/config.toml    Miri flags
.gitignore            target/, Nix's result links, direnv
src/, tests/          starter code that passes the lint set as-is
                      (a workspace puts these under crates/<name>/ and
                      crates/<name>-core/ instead)
AGENTS.md             the lint policy, and what to do when a lint fires
README, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT
LICENSE-MIT / LICENSE-APACHE (a workspace member carries its own copies)
.github/              7 workflows, dependabot, issue + PR templates
```

### The lint policy

`[lints.rust]` carries 27 lints. `[lints.clippy]` enables four groups —
`pedantic` and `nursery` at **deny**, `restriction` and `cargo` at warn — and
then turns off, one at a time and with a written reason, the lints that are
wrong for a normal crate. `just clippy` and CI run `cargo clippy --all-targets
-- -D warnings`, so warn and deny both fail the build; the difference shows only
in a bare `cargo clippy` (a warning or an error) -- `cargo check` runs no clippy
lint at all.

On top of the groups, the operations that end a process without returning an
error are denied by name: `unwrap_used`, `expect_used`, `panic`,
`panic_in_result_fn`, `unreachable`, `unimplemented`, `todo`, `exit`,
`indexing_slicing`, `string_slice`, `arithmetic_side_effects`,
`unchecked_time_subtraction`, and `as_conversions`.

This is stricter than most crates want, and that is the point of it being a
template: it is far easier to delete a lint you have decided against than to
retrofit one onto a codebase that has been ignoring it for a year. `AGENTS.md`
in the generated project explains each rule and how to opt out at a single site
with `#[expect(lint, reason = "...")]`.

### The CI workflows

- `rust-ci.yml` — check, test (including doctests), Miri, clippy with `-D
  warnings`, MSRV, `cargo fmt --check`, and a rustdoc build with warnings
  denied. rustup obeys `rust-toolchain.toml` over a toolchain action's default,
  so the stable jobs set `RUSTUP_TOOLCHAIN=stable`, which outranks the file;
  the MSRV job reads `rust-version` out of `Cargo.toml` at run time and fails
  if `rust-toolchain.toml` names another version.
- `rust-audit.yml` — `cargo audit` on every manifest change and nightly.
- `dependency-review.yml` — license and advisory review on pull requests.
- `dependabot-automerge.yml` — auto-merges patch/minor bumps. Read the setup
  comment at the top: without required status checks it merges things CI never
  gated.
- `style-check-dprint.yml`, `style-check-cocogitto.yml` — formatting and
  Conventional Commits: every commit (no tag needed), and a pull request's title,
  which a squash merge makes the commit.
- `nix.yml` — `nix flake check`: the flake's clippy, rustfmt, rustdoc and test
  derivations built, and every system it declares evaluated.

Every action is pinned to a commit, its version in a comment; Dependabot moves
them. Its Cargo bumps are `build(deps)` commits, which enter the changelog, and
its action bumps `ci(deps)`, which do not.

### The changelog and `just release`

There is no `CHANGELOG.md` until the first release writes one: git-cliff
generates it from the commits (`cliff.toml`), never a hand. `just changelog
--unreleased` previews the next section. `just release <major|minor|patch>`
refuses a dirty tree, another branch, a stale `main`, a version below
Cargo.toml's or an empty release; runs `just checks`; then bumps the version
(the workspace's intra-member pins too), writes the changelog, commits, tags
`v<version>` -- the first release `v0.1.0`, what Cargo.toml starts at -- pushes
the commit and the tag atomically, and runs `cargo publish --workspace`. Each
heading links its GitHub compare view, from Cargo.toml's `repository`.

### Nix

`nix develop` gives the toolchain `rust-toolchain.toml` pins (read by
[rust-overlay](https://github.com/oxalica/rust-overlay), so the MSRV is written
once) and every tool `just checks` and `just release` call; `just miri` enters
the flake's nightly `miri` shell itself. `nix flake check` builds clippy,
rustfmt, rustdoc and the tests offline in the sandbox; `nix build` the binary
(every layout but `lib`). The systems are those the flake's `nixos-unstable`
input supports: x86_64 and aarch64 Linux, Apple silicon. The
template ships no `flake.lock` -- it would age in the template; the first `nix`
command writes one, and the generated README says to commit it.

`release.yml` is deliberately **not** included. It is generated from
`dist-workspace.toml` by `dist init`, so run that once in the new project and
commit what it writes; a copy shipped here would pin you to whatever `dist`
version this template was built against.

## Developing this template

```sh
python3 -m venv .venv    # Python 3.11+ (tomllib); a venv, as distributions lock pip
.venv/bin/pip install python-liquid==2.3.4 pyyaml==6.0.3
.venv/bin/python tools/render-check.py
```

`tools/render-check.py` renders every templated file for all 24 combinations of
`project_kind` × `license` × empty-or-present email, then checks that nothing is
left unexpanded, that the result still parses as TOML/YAML/JSON -- and as Nix,
when `nix-instantiate` is on `PATH` -- and that the manifest matches the chosen
layout. It also guards config invariants that otherwise fail silently:

- **Every referenced variable is declared.** When Liquid meets an unknown
  variable, cargo-generate catches the error, substitutes an empty string and
  re-renders. A misspelled placeholder therefore does not fail — it renders as
  nothing, and a "no leftover `{{`" check cannot see it.
- **No file on the `exclude` list contains a placeholder**, since those files are
  copied verbatim and would ship the placeholder unexpanded.
- **Every `ignore` entry is a literal path that exists.** `ignore` is not
  glob-matched: cargo-generate joins each entry onto its working copy of the
  template and removes it -- before rendering, so an entry spells a path as the
  template does, `crates/{{project-name}}-core/LICENSE-MIT` included. A pattern
  like `tests/**` resolves to nothing and silently ships the file that was meant
  to be dropped.
- **The workspace members' licence copies equal the root's**, byte for byte.

The second check guards the sharpest edge in this template. These files are
copied **verbatim** and never processed by Liquid:

- `.github/workflows/**` — GitHub Actions expressions. Some use `||` inside an
  interpolation, which is not valid Liquid and aborts generation outright.
- `cliff.toml` — git-cliff's Tera templates. Its conditionals happen to *be*
  valid Liquid, so they would be silently evaluated and the changelog config
  quietly gutted. This one fails without an error message.
- `justfile` — just's own interpolation shares Liquid's double-brace syntax.

Anything project-specific added to those three must be derived at run time
instead, the way the MSRV job derives its toolchain version and `just changelog`
the repository.

`.github/workflows/template-smoke-test.yml` does the real end-to-end check,
weekly, on pushes to `main` and on every pull request: render-check; all 24
answer combinations through the actual `cargo-generate` (each manifest parsed,
each licence file where its choice puts it, `dprint check`); for each
`project_kind`, a generated project's git hooks installed and shown to refuse an
unformatted file, a bad message and a pushed revert, then the project put
through its own `just` recipes (clippy
on the pinned MSRV and on stable, Miri on nightly, `cargo audit`, `cog check`),
`dprint check`, `just changelog` and `cargo package`, and for the workspace two
`just release`s against a bare remote; and each flake through `nix flake check`
and `nix build`. A template whose output does not compile is worse than no
template, and this is the only thing that proves it does.

## Verification status

The template is driven end to end with the real tooling, not reasoned about.
With **cargo-generate 0.25.0**, **rustc / clippy 1.97.0** (the default MSRV),
**just 1.58.0**, **cocogitto 7.0.0**, **git-cliff 2.13.1**, **cargo-audit
0.22.2** and **dprint 0.61.0 with the markdown 0.26.0 and TOML 0.9.0 plugins**,
all 24 combinations -- `bin`, `lib`, `both` and `workspace`, × the three
licences, × email present and absent -- generate and, after their first commit,
pass:

```
just --fmt --check --unstable
just cargo-check test clippy fmt-check docs-check dprint-check cog audit
just changelog --unreleased
cargo package --workspace --locked
```

Also confirmed by running it, not by reading it:

- The release recipe, against a bare remote: the first `just release minor`
  tags `v0.1.0` and writes the changelog; a second, after a `build(deps)` and a
  `fix!` commit, bumps to `v0.2.0` -- Cargo.toml, Cargo.lock and the
  intra-workspace pin -- groups the breaking change first, leaves the release
  commit out, links the compare view, and pushes commit and tag together; it
  refuses an empty release, a dirty tree and an unknown level. `just checks`
  still passes after it. (`cargo publish` stopped at the missing token.)
- Every conditional drops exactly the right files, for all four layouts and all
  three licence choices, a workspace member's licence copies included.
- The workspace's hand-written `Cargo.lock` is byte-identical to what
  `cargo generate-lockfile` produces, which is what makes `--locked` work from
  the first commit.
- The workspace lint policy is genuinely inherited: injecting `v[0] + 1` into a
  member fails clippy with `indexing may panic` and `arithmetic operation that
  can potentially result in unexpected side-effects`.
- `cargo publish --workspace --dry-run` packages and "uploads" the members in
  dependency order.
- The flake of every layout evaluates on all three systems (`nix flake check
  --no-build --all-systems`, Nix 2.34.6, nixpkgs-unstable of 2026-10-06,
  rust-overlay of 2026-10-07) and is `nixfmt`-clean; this is how x86_64-darwin,
  which nixpkgs-unstable has dropped, was found and removed.
- The answer validation refuses an MSRV below 1.90, a `"` or `\` in the
  description or author, a sixth keyword and an uppercase category.
- `cargo`'s `[env]` reaches a target runner, which is how Miri's runner gets
  `.cargo/config.toml`'s `MIRIFLAGS`.
- `just test` fails, rather than skipping the doctests, when `jq` is missing;
  `just valgrind` (valgrind 3.22) runs clean on `both`, and a target it fails
  keeps its own report.
- The smoke test's combinations and release steps, run locally as written
  (`just miri` standing in as a native `cargo test`): the 24 generations with
  their licence files and `dprint check`, and the two releases with their tags,
  version and compare link, the empty third refused.
- The git hooks, run as the smoke test's step does, for `bin`, `lib` and
  `workspace`: an unformatted file, a message cog rejects and a pushed revert
  refused, each for that reason, and a clean push accepted. The two releases
  then commit and push through them, the tag included; a release commit a hook
  refuses -- the first, too -- leaves a clean tree and no tag. A merge commit
  passes whatever its message, as CI ignores merges.
- The workflows pass actionlint 1.7.12 with shellcheck 0.9.0, and the justfile's
  shell recipes and the hooks pass shellcheck.

What this does **not** cover -- the smoke-test workflow is what does:

- **Builds under Nix.** The flake's derivations were evaluated, never built:
  this environment reaches no binary cache.
- **Miri, and clippy on a newer stable.** No nightly or newer toolchain could be
  installed here, so `just miri` never ran, and lints added after 1.97 (stable
  is 1.99 at the time of writing) may fire on the starter code.
- **The MSRV floor's toolchain** (1.90), and dprint's plugins as fetched from
  `plugins.dprint.dev`: this environment cannot reach it, so the same versions
  ran from their npm packages.
- **cargo-dist** (`dist init`) and **GitHub Actions itself**: the workflows are
  linted, not run.

## Attribution

The lint policy, workflows, `justfile`, `cliff.toml`, `cog.toml` and community
documents are adapted from [`veralvx/imi`](https://github.com/veralvx/imi),
dual-licensed MIT OR Apache-2.0.

Two deliberate divergences from the source: `clippy::as_conversions` is denied
here where imi allows it (imi relies on the pedantic `cast_*` lints instead),
and `pedantic`/`nursery` are at deny rather than warn.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  <http://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or
  <http://opensource.org/licenses/MIT>)

at your option.
