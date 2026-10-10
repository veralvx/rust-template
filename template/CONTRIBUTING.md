# Contributing to `{{project-name}}`

Thank you for considering contributing to `{{project-name}}`!

## Prerequisites

To build and test `{{project-name}}` locally you will need either **Nix** --
`nix develop` gives every tool below at the versions `flake.lock` pins, the
toolchain read from `rust-toolchain.toml`, and `just miri` its nightly shell --
or, installed yourself:

- **Rust {{msrv}} or later** (pinned in `rust-toolchain.toml`, so `rustup` will
  fetch it automatically the first time you build).
- **[just](https://github.com/casey/just)** — the command runner this project's
  automation is written in.
- **[jq](https://jqlang.org/)** — `just test` asks `cargo metadata` through it
  whether there are doctests to run.
- **[dprint](https://dprint.dev/)** — formats the Markdown and TOML.
- **[cocogitto](https://docs.cog.tools/)** (`cog`) — enforces Conventional
  Commits.
- **A nightly toolchain with the `miri` component**
  (`rustup toolchain install nightly --component miri`). `just checks` runs
  `cargo +nightly miri test`, and so does CI.
- **cargo-audit** (`cargo install cargo-audit`), for the dependency advisory
  scan.
- **[git-cliff](https://git-cliff.org/)**, for maintainers: `just changelog`
  and `just release` write the changelog with it.

The nightly Miri toolchain and cargo-audit are easy to miss: without them
`just checks` fails on tooling rather than on anything wrong with your change.

## Setup

1. Fork this repository and create your branch from `main`.
2. Clone your fork locally:

```sh
git clone https://github.com/<you>/{{project-name}} && cd {{project-name}}
```

3. Optionally, `just install-hooks`: `.githooks/` then checks formatting before
   each commit, the message as a Conventional Commit, and every pushed commit's
   message before a push -- what CI would refuse, minutes earlier. They need
   `just`, `cargo`, `dprint` and `cog` on `PATH` (inside `nix develop`, with
   Nix); `git config --unset core.hooksPath` turns them off.

## Guidelines

Before you start, read [AGENTS.md](AGENTS.md). It documents the lint policy —
which lints are on, why, and what to do when one fires — and applies to human
and AI-assisted contributions alike.

The short version: this crate denies the operations that can panic, abort or
silently truncate (`unwrap`, `expect`, `panic!`, indexing, unchecked
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
warnings denied, `dprint check`, `cog check`, and `cargo audit` -- the set the
workflows under `.github/workflows/` run, here on the toolchain
`rust-toolchain.toml` pins (Miri on nightly). CI's Rust jobs (check, test,
clippy, fmt, docs) run on the latest stable, where a lint newer than the MSRV
can still fire; the pinned toolchain runs there in the MSRV job (check, test)
and in `nix.yml`, the flake's checks -- clippy, rustfmt, rustdoc and the tests
in the Nix sandbox -- which `nix flake check` runs locally.

## Creating a Pull Request

1. Ensure your code passes `just checks` locally.
2. Open a Pull Request against the `main` branch, titled as a conventional
   commit: a squash merge makes the title the commit, and so a changelog entry
   (CI checks it).
3. In your PR description, outline the problem you are solving. Link the
   relevant issue (e.g. `Fixes #123`), if any.
4. Wait for a maintainer to review your code.

## Releasing (maintainers)

`just release <major|minor|patch>`, from a clean `main` equal to `origin/main`,
CI green on it: the recipe runs no tests. It bumps the version, writes
`CHANGELOG.md` with git-cliff, commits, tags `v<version>` (the first release
`v0.1.0`), pushes the commit and the tag together and runs `cargo publish --workspace`.{% if project_kind != "lib" and container_image %} The tag runs
`image.yml`: the binary's OCI image to GHCR, from the flake's `image` (`nix
build .#image` builds it here).{% endif %} Before the
first one:

- `cargo login` with a crates.io token -- otherwise the tag is pushed and
  nothing is published; run `cargo publish --workspace` again once logged in.
- The commits since the last tag must hold a change a user meets (`feat`,
  `fix`, `perf`, `build`...): `chore`, `ci` and `style` alone make no release.
- The release pushes to `main` directly: with "Require a pull request before
  merging" on, the maintainer cutting it needs the rule's bypass. A refused
  push leaves the commit and the tag local -- push them again with
  `git push --atomic origin main v<version>` once allowed.
