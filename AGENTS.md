# AGENTS.md

Repository rules for `rust-template`, the cargo-generate template. These apply to every
contributor, human or AI-assisted. The tools, the checks and the release are
[CONTRIBUTING.md](CONTRIBUTING.md)'s.

## 1. Two repositories in one

- **`template/`** is what a generated project gets: every file in it, rendered by cargo-generate's
  Liquid unless `template/cargo-generate.toml` excludes it. Its own rules -- the lint policy, what
  may panic, the tests -- are [template/AGENTS.md](template/AGENTS.md)'s, and they hold for what it
  generates.
- **The rest** is this repository's: the smoke test and render-check that prove the template, and
  the files any repository has (these, the hooks, the workflows, the flake).

A change to `template/` is judged by what it generates, never by its text alone: `just smoke
<kind>` generates it with the real cargo-generate and runs the project's own checks.

## 2. What cargo-generate does with a file

- **A placeholder names a declared variable.** cargo-generate renders an unknown one as an empty
  string, without a word; `just render-check` refuses it.
- **A file with another `{{ }}` or `{% %}` syntax is excluded** (copied verbatim): the workflows
  (GitHub's expressions), the justfile (just's) and `cliff.toml` (Tera, which Liquid would evaluate
  silently). An excluded file holds no placeholder: render-check refuses one.
- **Every answer combination renders and parses.** render-check renders each templated file for
  48 combinations and parses the TOML, YAML, JSON and Nix; whitespace is the smoke test's, as
  python-liquid trims one newline liquid-rust keeps.

## 3. Copies stay copies

These files are the template's own, copied here, and render-check holds each byte for byte equal to
its original under `template/`: `cog.toml`, `cliff.toml`, `.editorconfig`, the `commit-msg` and
`pre-push` hooks, the dprint, Conventional Commits and Dependabot auto-merge workflows, and the
justfiles' `shell-check`, `shfmt` and `shfmt-recipes` recipes. Change the original, then copy it;
its wording must hold in both places.

## 4. Formats

Shell is formatted by shfmt (`.editorconfig` holds its style) and passes ShellCheck -- a justfile
script recipe included: `just shell-check` reads them out of `just --dump`, and refuses one that
splices a value into its text (it takes arguments). The Nix is nixfmt's, the justfiles just's own
(`nix fmt` formats the three); the Markdown and TOML, dprint's; `just fmt` runs them all. The
workflows pass actionlint. Actions are pinned to a full commit SHA, the version in a comment, as
Dependabot keeps them.

## 5. Comments: only what is essential

A comment says what the code cannot: why it is so, the source it follows, the constraint it
keeps. Make it concise and precise -- a line where a line does -- and never restate the code:
that is noise, and it goes stale. A change that falsifies a comment rewrites it.

## 6. Commits

[Conventional Commits](https://www.conventionalcommits.org/) are enforced by `cog check` locally
and in CI. The changelog is generated from the commits (`cliff.toml`), so the subject line is
what a template user reads; `chore`, `ci` and `style` commits stay out of it, and `!` or a
`BREAKING CHANGE` footer -- a prompt renamed, a file a generated project no longer has -- lists a
commit first:

```text
feat(template): ask for the MSRV
fix(template): keep the workspace's members on one version
docs: the release steps
feat!: rename the `kind` prompt to `project_kind`
```

The git hooks (`just install-hooks`) check the same before a commit and a push; never bypass them
with `--no-verify`. `git revert` writes `Revert "..."`, which CI refuses: reword it as
`revert: ...`.

## 7. Before you claim a change is done

Run `just checks` -- render-check, the shell, the workflows, dprint, the commit messages and the
flake -- and, for a change under `template/`, `just smoke <kind>` for each of `bin`, `lib`, `both`,
`workspace`. Together they are what CI runs, but the smoke test's releases and its other jobs: CI's.
Reporting "done" on a change that has not passed them is the one thing that wastes the most time
here.

If a check fails for reasons unrelated to your change, say so explicitly rather than working
around it -- a broken check that everyone routes around stops protecting anything.
