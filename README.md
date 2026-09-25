# rust-crate-template

A [`cargo-generate`](https://github.com/cargo-generate/cargo-generate) template
for a Rust crate that starts out with the whole toolchain already wired up:
a deliberately strict lint policy, GitHub Actions CI, Conventional Commits,
changelog generation, dependency auditing, and a `justfile` that runs the same
checks locally that CI runs remotely.

The configuration is adapted from [`veralvx/imi`](https://github.com/veralvx/imi)
(MIT OR Apache-2.0). See [Attribution](#attribution).

## Usage

```sh
cargo install cargo-generate
cargo generate --git https://github.com/YOUR-USER/rust-crate-template template
```

The trailing `template` is the sub-folder that holds the template itself; the
repository root holds this README and the template's own CI. `cargo-generate`
will find it on its own if you omit the argument, but naming it is unambiguous.

From a local checkout:

```sh
cargo generate --path ./rust-crate-template template
```

Everything can be answered non-interactively, which is what the smoke test does:

```sh
cargo generate --path ./rust-crate-template template \
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
| `description`     | `A Rust crate.`     | `package.description`, crate-level rustdoc, README                  |
| `project_kind`    | `bin`               | `bin`, `lib`, `both`, or `workspace` — see below                    |
| `author_name`     | —                   | `package.authors`, license copyright line                           |
| `author_email`    | *(empty)*           | `package.authors`, `cog.toml`, code of conduct — omitted if blank   |
| `github_username` | —                   | repository URL, security advisory link, binstall URL                |
| `license`         | `MIT OR Apache-2.0` | `package.license`, which `LICENSE-*` files are kept, README         |
| `msrv`            | `1.97`              | `package.rust-version`, `rust-toolchain.toml`, CI's MSRV job        |
| `keywords`        | `rust`              | `package.keywords` (comma-separated, max 5)                         |
| `categories`      | `development-tools` | `package.categories` (comma-separated, max 5)                       |

Every answer is validated by a regex at the prompt, so a typo is caught before
generation rather than at `cargo publish`. `keywords` and `categories` follow
crates.io's rules (max 5 each, 20 characters per keyword), and neither may be
empty: `clippy::cargo_common_metadata` is enabled and requires both.

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

Two things worth knowing if you pick it:

- `cargo publish --workspace` publishes members in dependency order. `just
  release` bumps the root version *and* the version on any dependency line that
  also carries a `path =` — those are the intra-workspace ones, and a stale one
  makes publishing fail.
- A new member that omits `[lints] workspace = true` silently opts out of the
  entire lint policy. There is no warning for it; it is the one footgun the
  workspace layout adds.

### Why the MSRV prompt behaves the way it does

The hard floor is **1.85**, because the template uses edition 2024 and nothing
older can compile it. The default is **1.97**, which is the version at which
every lint name in the manifest exists.

Three of the names are newer than 1.85: `clippy::unchecked_time_subtraction`
arrived in 1.92 (renamed from `unchecked_duration_subtraction`), and
`clippy::inline_trait_bounds` and `clippy::inline_modules` arrived in 1.97.

Choosing an MSRV between 1.85 and 1.96 is supported and safe. The consequence is
narrow and was measured rather than guessed, by generating the project and
running the toolchains:

- `cargo check` and `cargo test` are **completely silent** — rustc ignores
  `clippy::` names it does not recognise, so an older MSRV job sees nothing.
- `cargo clippy` prints `warning[E0602]: unknown lint` for each name it does not
  know and **exits 0**, so it fails no build, including under `-D warnings`.
- You only see those warnings locally, because `rust-toolchain.toml` pins your
  toolchain to the MSRV. The CI clippy job runs on stable, where all three
  names exist.

Measured at the floor, on rustc 1.85.1 with clippy 0.1.85: `cargo check
--locked`, `cargo test`, `cargo fmt --check` and `cargo doc -D warnings` all
pass for `both` and `workspace`, and `cargo clippy -- -D warnings` **exits 0**
having reported exactly those three names as unknown and nothing else.

## What you get

```
Cargo.toml            strict lint policy, release profile, crates.io metadata
Cargo.lock            committed, so CI's --locked builds work from commit one
clippy.toml           test code exempted from the panic-family lints
rust-toolchain.toml   pinned to the MSRV
rustfmt.toml          edition 2024, 100 columns
dprint.json           Markdown + TOML formatting
cliff.toml            git-cliff changelog generation
cog.toml              cocogitto / Conventional Commits
dist-workspace.toml   cargo-dist config (binaries only)
justfile              `just checks` = the nine steps CI runs
.cargo/config.toml    Miri flags
src/, tests/          starter code that passes the lint set as-is
                      (a workspace puts these under crates/<name>/ and
                      crates/<name>-core/ instead)
AGENTS.md             the lint policy, and what to do when a lint fires
README, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, CHANGELOG
LICENSE-MIT / LICENSE-APACHE
.github/              6 workflows, dependabot, issue + PR templates
```

### The lint policy

`[lints.rust]` carries 27 lints. `[lints.clippy]` enables four groups —
`pedantic` and `nursery` at **deny**, `restriction` and `cargo` at warn — and
then turns off, one at a time and with a written reason, the lints that are
wrong for a normal crate. CI runs `cargo clippy --all-targets -- -D warnings`,
so warn and deny both fail the build; the difference is only whether `cargo
check` stops immediately.

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
  denied. The MSRV job reads `rust-version` out of `Cargo.toml` at run time, so
  there is no second copy of the version to drift.
- `rust-audit.yml` — `cargo audit` on every manifest change and nightly.
- `dependency-review.yml` — license and advisory review on pull requests.
- `dependabot-automerge.yml` — auto-merges patch/minor bumps. Read the setup
  comment at the top: without required status checks it merges things CI never
  gated.
- `style-check-dprint.yml`, `style-check-cocogitto.yml` — formatting and
  Conventional Commits.

`release.yml` is deliberately **not** included. It is generated from
`dist-workspace.toml` by `dist init`, so run that once in the new project and
commit what it writes; a copy shipped here would pin you to whatever `dist`
version this template was built against.

## Developing this template

```sh
python3 -m pip install python-liquid pyyaml
python3 tools/render-check.py
```

`tools/render-check.py` renders every templated file for all 18 combinations of
`project_kind` × `license` × empty-or-present email, then checks that nothing is
left unexpanded, that the result still parses as TOML/YAML/JSON, and that the
manifest matches the chosen layout. It also guards three config invariants that
otherwise fail silently:

- **Every referenced variable is declared.** When Liquid meets an unknown
  variable, cargo-generate catches the error, substitutes an empty string and
  re-renders. A misspelled placeholder therefore does not fail — it renders as
  nothing, and a "no leftover `{{`" check cannot see it.
- **No file on the `exclude` list contains a placeholder**, since those files are
  copied verbatim and would ship the placeholder unexpanded.
- **Every `ignore` entry is a literal path that exists.** `ignore` is not
  glob-matched: cargo-generate joins each entry onto the output directory and
  removes it. A pattern like `tests/**` resolves to nothing and silently ships
  the file that was meant to be dropped.

That last check guards the sharpest edge in this template. These files are
copied **verbatim** and never processed by Liquid:

- `.github/workflows/**` — GitHub Actions expressions. Some use `||` inside an
  interpolation, which is not valid Liquid and aborts generation outright.
- `cliff.toml` — git-cliff's Tera templates. Its conditionals happen to *be*
  valid Liquid, so they would be silently evaluated and the changelog config
  quietly gutted. This one fails without an error message.
- `justfile` — just's own interpolation shares Liquid's double-brace syntax.

Anything project-specific added to those three must be derived at run time
instead, the way the MSRV job derives its toolchain version.

`.github/workflows/template-smoke-test.yml` does the real end-to-end check
weekly and on every push: it generates a project with actual `cargo-generate`
and then runs `cargo clippy -- -D warnings`, the test suite, doctests, `cargo
fmt --check`, a docs build, `cargo package` and `dprint check` inside it. A
template whose output does not compile is worse than no template, and this is
the only thing that proves it does.

## Verification status

The template is driven end to end with the real tooling, not reasoned about.
With **cargo-generate 0.23.0**, **rustc 1.91.1 / clippy 0.1.91** and **just
1.58.0** — and separately at the MSRV floor on **rustc 1.85.1 / clippy 0.1.85**
— all four `project_kind` values — `bin`, `lib`, `both` and `workspace`
— generate and then pass:

```
cargo check   --workspace --all-targets --locked
cargo clippy  --workspace --all-targets --locked -- -D warnings
cargo test    --workspace --all-targets --locked
cargo test    --workspace --doc --locked      (skipped, correctly, for bin)
cargo fmt     --all -- --check
cargo doc     --workspace --no-deps --all-features --locked   (RUSTDOCFLAGS=-D warnings)
cargo package --workspace --locked
just --fmt --check --unstable ; just --list
```

Also confirmed by running it, not by reading it:

- The three verbatim files come out byte-identical to their source, and no
  placeholder survives anywhere else.
- Every conditional drops exactly the right files, for all four layouts and all
  three licence choices, with the author email present and absent.
- The workspace's hand-written `Cargo.lock` is byte-identical to what
  `cargo generate-lockfile` produces, which is what makes `--locked` work from
  the first commit.
- The workspace lint policy is genuinely inherited: injecting `v[0] + 1` into a
  member fails clippy with `indexing may panic` and `arithmetic operation that
  can potentially result in unexpected side-effects`. Compiling is not the same
  as enforcing.
- `cargo publish --workspace --dry-run` packages members in dependency order,
  and the inherited `readme.workspace = true` really does land `README.md`
  inside each member's `.crate`.
- The release recipe's version rewrite touches only the package version and the
  intra-workspace dependency pinned to it; its read-back guard fires on a
  manifest it cannot rewrite.
- Generation with no sub-folder argument finds `template/` on its own without
  leaking repository files, and the answer validation rejects a below-floor
  MSRV, a sixth keyword, an over-long keyword, a malformed email, an uppercase
  category and an out-of-choice value.

What this does **not** cover:

- **Lints newer than 1.91.** Current stable is 1.98. A restriction or nursery
  lint added since could fire on the starter code, and the three lint names
  newer than 1.91 could not be exercised. The smoke-test workflow runs clippy on
  stable and is what catches this.
- **dprint, cocogitto, git-cliff, Miri and cargo-dist.** dprint's plugins are
  fetched from a CDN this environment cannot reach, so `dprint check` has never
  run; the Markdown and TOML here follow the formatter's conventions by
  inspection. `cog.toml`, `cliff.toml` and `dist-workspace.toml` are likewise
  unexercised.
- **The `release` recipe end to end.** Its version rewrite and guard were tested
  in isolation; the recipe has never been run to the point of tagging or
  publishing.

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
