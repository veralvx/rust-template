# AGENTS.md

Repository rules for `{{project-name}}`. These apply to every contributor,
human or AI-assisted. The toolchain, the tests' rules and the release are
[CONTRIBUTING.md](CONTRIBUTING.md)'s{% if project_kind == "workspace" %}; the workspace's layout,
[README.md](README.md)'s{% endif %}.

## 1. The lint policy is the design

{% if project_kind == "workspace" -%}
The workspace root `Cargo.toml` enables `clippy::pedantic` and `clippy::nursery`
at **deny**, plus the whole `clippy::restriction` and `clippy::cargo` groups at
warn
{%- else -%}
`Cargo.toml` enables `clippy::pedantic` and `clippy::nursery` at **deny**, plus
the whole `clippy::restriction` and `clippy::cargo` groups at warn
{%- endif %} — and CI runs
`cargo clippy --all-targets -- -D warnings`, so a warning fails the build
exactly like a denial does.

`restriction` is not designed to be enabled wholesale. That is deliberate here:
the group is enabled and the lints that are wrong *for this project* are turned
off one at a time, each with a written reason, in the {% if project_kind == "workspace" %}`[workspace.lints.clippy]`{% else %}`[lints.clippy]`{% endif %} table.
The alternative — enabling lints one at a time — silently opts out of every lint
written after the list was made.

**Never add a blanket allow to silence a new lint.** Either fix the site, or add
the allow to `Cargo.toml` with a comment saying why the lint is wrong for this
codebase.

## 2. Denied: anything that panics, aborts or silently truncates

```
unwrap_used   expect_used   panic   panic_in_result_fn   unreachable
unimplemented   todo   exit   indexing_slicing   string_slice
arithmetic_side_effects   unchecked_time_subtraction   as_conversions
```

Each has a total counterpart. Use it:

- `a + b` → `a.checked_add(b).ok_or(...)?`, or `.saturating_add(b)` /
  `.wrapping_add(b)` when the clamp or the wrap is the behaviour you actually
  want.
- `v[i]` → `v.get(i).ok_or(...)?`
- `&s[a..b]` → `s.get(a..b).ok_or(...)?`
- `x.unwrap()` → `x.ok_or(...)?`, `match`, or `let ... else`
- `panic!("...")` → `return Err(...)`
- `n as u32` → `u32::try_from(n)?`
- `process::exit(1)` → return an error from `main`

`unchecked_time_subtraction` is clippy 1.92's name for pedantic's
`unchecked_duration_subtraction`: below 1.92 the pinned clippy calls the name
unknown, yet `pedantic` still denies `Instant - Duration`; only
`Duration - Duration`, which 1.92 added, is left to CI's stable clippy.

`exit` is denied for a specific reason: it terminates immediately and skips
every `Drop` on the way out, so buffered output goes unflushed and cleanup does
not run. Return an error from `main` instead.

Test code is exempt from four of these via `clippy.toml` (`unwrap_used`,
`expect_used`, `indexing_slicing`, `panic`) — an `unwrap` in a test is an
assertion, and a panic is how a test reports failure.

## 3. Silence a lint at the site, with a reason

```rust
#[expect(
    clippy::indexing_slicing,
    reason = "the slice is a fixed-size array from a const generic; \
              the index is checked against N above"
)]
```

Use `#[expect]`, never `#[allow]` — `clippy::allow_attributes` and
`clippy::allow_attributes_without_reason` are on. `#[expect]` fails
`just clippy` and CI (`-D warnings`) once the lint stops firing, so a
justification cannot outlive the code it justified.

A reason that restates the lint (`reason = "we need to index here"`) is not
a reason. Say what makes the operation safe.

## 4. Comments: only what is essential

A comment says what the code cannot: why it is so, the source it follows, the
constraint it keeps. Make it concise and precise — a line where a line does —
and never restate the code: that is noise, and it goes stale. A change that
falsifies a comment rewrites it.

## 5. Commits

[Conventional Commits](https://www.conventionalcommits.org/) are enforced by
`cog check` locally and in CI. The changelog is generated from the commits
(`cliff.toml`), so the subject line is user-facing text; `chore`, `ci` and
`style` commits stay out of it, and `!` or a `BREAKING CHANGE` footer lists a
commit first:

```
feat(parser): accept bare keys in section headers
fix: reject a trailing separator instead of panicking
docs: explain why exit is denied
build(deps): bump serde from 1.0.200 to 1.0.201
```

The git hooks (`just install-hooks`) check the same before a commit and a push;
never bypass them with `--no-verify`. `git revert` writes `Revert "..."`, which
CI refuses: reword it as `revert: ...`.

## 6. Before you claim a change is done

Run `just checks`: the nine checks CI runs, on the toolchain
`rust-toolchain.toml` pins (Miri on nightly). CI's Rust jobs (check, test,
clippy, fmt, docs) run on the latest stable, where a lint newer than the MSRV
can still fire; the pinned toolchain runs there in the MSRV job (check, test)
and in `nix.yml`, the flake's checks — clippy, rustfmt, rustdoc and the tests
in the Nix sandbox — which `just checks` leaves to `nix flake check`.
Reporting "done" on a change that has not passed them is the one thing that
wastes the most time here.

If a check fails for reasons unrelated to your change, say so explicitly rather
than working around it — a broken check that everyone routes around stops
protecting anything.
