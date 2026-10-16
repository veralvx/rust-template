---
name: Bug Report
about: Report a generation that fails, or a generated project that misbehaves
title: "bug: "
labels: "bug"
assignees: ""
---

## Context

- **cargo-generate version (`cargo generate --version`):**
- **Template version (the tag) or commit:**
- **The answers given** (the `cargo generate` command, with its `-d` values):

## Expected Behavior

[Describe what should have happened.]

## Actual Behavior

[Describe the failure. Include the error as printed: cargo-generate's, or the generated project's
`just checks` or CI's.]

## Reproduction

```sh
cargo generate --git https://github.com/veralvx/rust-template template ...
```
