# Contributing to `{{project-name}}`

Thank you for considering contributing to `{{project-name}}`!

## Prerequisites

To build and test `{{project-name}}` locally you will need:

- **Rust {{msrv}} or later** (pinned in `rust-toolchain.toml`, so `rustup` will
  fetch it automatically the first time you build).
- **[just](https://github.com/casey/just)** — the command runner this project's
  automation is written in.
- **[dprint](https://dprint.dev/)** — formats Markdown, TOML, YAML and JSON.
- **[cocogitto](https://docs.cog.tools/)** (`cog`) — enforces Conventional
  Commits.
- **A nightly toolchain with the `miri` component**
  (`rustup toolchain install nightly --component miri`). `just checks` runs
  `cargo +nightly miri test`, and so does CI.
- **cargo-audit** (`cargo install cargo-audit`), for the dependency advisory
  scan.

The last two are easy to miss: without them `just checks` fails on tooling
rather than on anything wrong with your change.

## Setup

1. Fork this repository and create your branch from `main`.
2. Clone your fork locally:

```sh
git clone https://github.com/{{github_username}}/{{project-name}} && cd {{project-name}}
```

## Guidelines

Before you start, read [AGENTS.md](AGENTS.md). It documents the lint policy —
which lints are on, why, and what to do when one fires — and applies to human
and AI-assisted contributions alike.

The short version: this crate denies the operations that can end the process
without returning an error (`unwrap`, `expect`, `panic!`, indexing, unchecked
arithmetic, `as`, `exit`). Reach for the total counterpart, or annotate the site
with `#[expect(lint, reason = "...")]` explaining why the lint is wrong there.

## Testing Strategy

- **Pure functions:** isolate logic from side effects wherever possible and
  cover it with unit tests.
- **Regressions:** if you are fixing a bug, include a test that reproduces the
  previous failure state.
{% if project_kind == "workspace" -%}
- **Public API:** `crates/{{project-name}}-core/tests/public_api.rs` is an
  integration test, so it sees only what a downstream dependent sees. Anything
  you intend to publish should be reachable from there.
- **Where logic goes:** in `crates/{{project-name}}-core`, not in the binary.
  Code in `crates/{{project-name}}` can only be exercised by running the
  process; code in the core crate can be unit-tested directly.
{% elsif project_kind != "bin" -%}
- **Public API:** `tests/public_api.rs` is an integration test, so it sees only
  what a downstream dependent sees. Anything you intend to publish should be
  reachable from there.
{% endif -%}
- **Doctests:** examples in rustdoc are compiled and run. `--all-targets` skips
  them, which is why `just test` runs `cargo test --doc` as a separate step
  whenever the package has a library target.

## Development Workflow

1. The [Conventional Commits](https://www.conventionalcommits.org/)
   specification is enforced on every commit.
2. Run the automated checks locally. This repository includes a `justfile` that
   mirrors the GitHub Actions pipeline:

```sh
just checks
```

That runs nine recipes in order: `cargo check`, the test suite, Miri,
`cargo clippy` with warnings denied, `cargo fmt --check`, a docs build with
warnings denied, `dprint check`, `cog check`, and `cargo audit`. If `just checks`
passes on your machine, your code should pass CI — the workflows under
`.github/workflows/` run the same set.

## Creating a Pull Request

1. Ensure your code passes `just checks` locally.
2. Open a Pull Request against the `main` branch.
3. In your PR description, outline the problem you are solving. Link the
   relevant issue (e.g. `Fixes #123`), if any.
4. Wait for a maintainer to review your code.
