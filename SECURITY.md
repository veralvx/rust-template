# Security Policy

## Supported Versions

Security updates are applied to the latest `main` branch and the most recent release. A project
already generated is its own: a fix here reaches it only when its maintainer applies it, so a fix
to a file the template generates says what to change in such a project.

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.** To report one, use the [Private
Vulnerability Reporting](https://github.com/veralvx/rust-template/security/advisories/new) feature
in this repository.

What counts: anything in this repository, or in a project generated from it, that runs or publishes
what it should not -- a workflow an outsider's pull request can make run their code or use a token,
a script that executes its input, a secret exposed, a release or a crate on crates.io or an image
published from what was not reviewed.

Please include the technical context needed to reproduce it:

- The version (tag) or commit affected, and the answers the project was generated with.
- The file and, for a workflow, the event that triggers it.
- Exact reproduction steps or a proof-of-concept.

You can expect an initial response within a few days. Please give us a
reasonable window to ship a fix before disclosing publicly.
