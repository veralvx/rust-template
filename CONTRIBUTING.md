# Contributing to `rust-template`

Thank you for considering contributing to `rust-template`!

## Prerequisites

Either **Nix** -- `nix develop` gives every tool below, at the versions `flake.lock` pins -- or,
installed yourself:

- **[cargo-generate](https://cargo-generate.github.io/cargo-generate/)** 0.25 or later, which the
  template is for (`just generate`, `just smoke`).
- **Python** 3.11 or later, for `just render-check`: it installs `tools/requirements.txt` into
  `.venv`.
- **[just](https://github.com/casey/just)** and **[jq](https://jqlang.org/)** -- the automation,
  and what it reads JSON with.
- **[ShellCheck](https://www.shellcheck.net/)** and **[shfmt](https://github.com/mvdan/sh)** --
  the shell's linter and formatter (its style is `.editorconfig`'s).
- **[actionlint](https://github.com/rhysd/actionlint)** -- lints the workflows, this repository's
  and the template's.
- **[dprint](https://dprint.dev/)** -- formats the Markdown and TOML.
- **[cocogitto](https://docs.cog.tools/)** (`cog`) -- enforces Conventional Commits.
- **[git-cliff](https://git-cliff.org/)**, for maintainers: `just changelog` and `just release`
  write the changelog with it.
- **[Nix](https://nixos.org)** for the last of `just checks`, the flake's checks (`just nix`), and
  for `just smoke`, which runs a generated project's checks in its own flake's shell.

## Setup

1. Fork this repository and create your branch from `main`.
2. Clone your fork:

```sh
git clone https://github.com/<you>/rust-template && cd rust-template
```

3. Optionally, `just install-hooks`: `.githooks/` then checks the shell, the workflows and dprint
   before each commit, the message as a Conventional Commit, and every pushed commit's message
   before a push -- what CI would refuse, minutes earlier. They need `just`, `jq`, `shellcheck`,
   `shfmt`, `actionlint`, `dprint` and `cog` on `PATH` (inside `nix develop`, with Nix);
   `git config --unset core.hooksPath` turns them off.

## Guidelines

Before you start, read [AGENTS.md](AGENTS.md): how `template/` and the rest differ, what
cargo-generate does with a file, which files are copies. It applies to human and AI-assisted
contributions alike.

## Development Workflow

1. The [Conventional Commits](https://www.conventionalcommits.org/) specification is enforced on
   every commit. A commit's subject is its changelog entry -- git-cliff writes the changelog from
   them at each release -- so write it for the template's users; a change to `template/` takes
   the scope `template`.
2. Run the checks. The `justfile` runs the workflows' commands:

```sh
just checks           # render-check, the shell, the workflows, dprint, cog, the flake's last
just render-check     # every templated file rendered for every answer combination, checked
just smoke workspace  # generated with cargo-generate, then its own `just checks` (each kind)
just generate bin     # target/bin/demo, to look at, committed once
just shell-check      # shellcheck and shfmt, this repository's (and template-shell-check)
just fmt              # every formatter the checks hold the files to, `nix fmt` last
```

`just` alone lists every recipe; `nix fmt` alone formats the Nix, the shell and the justfiles.

## Creating a Pull Request

1. Make sure `just checks` passes -- and, for a change under `template/`, `just smoke` for each
   kind (`bin`, `lib`, `both`, `workspace`).
2. Open a pull request against `main`, titled as a conventional commit: a squash merge makes the
   title its commit, and so a changelog entry (CI checks it). Describe the problem it solves, and
   link its issue (`Fixes #123`), if any.
3. Wait for a maintainer's review.

## Maintainers

### Repository settings

- The auto-merge workflow's settings are listed at the top of
  `.github/workflows/dependabot-automerge.yml`. Without required status checks, it merges bumps
  that CI never gated.
- Enable private vulnerability reporting (Settings → Code security): it is off by default, and
  [SECURITY.md](SECURITY.md) and the issue form point to it.

### Releasing

The template has no version file: a release is a tag, `v<version>`, which a user generates from with
`cargo generate --git https://github.com/veralvx/rust-template --tag v<version> template`. From a
clean `main` equal to `origin/main`, CI green on it:

```sh
just changelog --unreleased   # the section the release will write
just release <major|minor|patch>
```

The recipe shows every step, in order, and runs no tests -- CI's verdict on that commit is the
release's: it refuses a release with nothing in it, writes the changelog (git-cliff), commits,
tags `v<version>` and pushes the commit and the tag together. The first release is `0.1.0`,
whatever the level. The tag runs `release.yml`: the GitHub release, the changelog's new section as
its notes.

- The commits since the last tag must hold a change a user meets (`feat`, `fix`, `perf`,
  `build`...): `chore`, `ci` and `style` alone make no release.
- The release pushes to `main` directly: with "Require a pull request before merging" on, the
  maintainer cutting it needs the rule's bypass. A refused push leaves the commit and the tag
  local -- push them again with `git push --atomic origin main v<version>` once allowed.

## Updating the tools

This flake follows nixos-unstable, for cargo-generate 0.25; a generated project's tools are its own
flake's ([template/CONTRIBUTING.md](template/CONTRIBUTING.md)). The smoke test installs its own
tools in the workflow: move those by hand. Dependabot moves the actions, this repository's and the
template's in one pull request (the copies render-check holds equal move together), as
`build(deps)`, a changelog entry: they change what a project is generated with. It moves
render-check's Python packages too (`tools/requirements.txt`).
