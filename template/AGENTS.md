# AGENTS.md

Repository rules for `{{project-name}}`. These apply to every contributor,
human or AI-assisted.

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
off one at a time, each with a written reason, in the `[lints.clippy]` table.
The alternative — enabling lints one at a time — silently opts out of every lint
written after the list was made.

**Never add a blanket allow to silence a new lint.** Either fix the site, or add
the allow to `Cargo.toml` with a comment saying why the lint is wrong for this
codebase.

## 2. Denied: anything that ends the process without an error

```
unwrap_used   expect_used   panic   panic_in_result_fn   unreachable
unimplemented   todo   exit   indexing_slicing   string_slice
arithmetic_side_effects   unchecked_time_subtraction   as_conversions
```

Each has a total counterpart. Use it:

- `a + b` → `a.checked_add(b)?`, or `.saturating_add(b)` / `.wrapping_add(b)`
  when the clamp or the wrap is the behaviour you actually want.
- `v[i]` → `v.get(i).ok_or(...)?`
- `&s[a..b]` → `s.get(a..b).ok_or(...)?`
- `x.unwrap()` → `x.ok_or(...)?`, `match`, or `let ... else`
- `panic!("...")` → `return Err(...)`
- `n as u32` → `u32::try_from(n)?`
- `process::exit(1)` → return an error from `main`

`exit` is denied for a specific reason: it terminates immediately and skips
every `Drop` on the way out, so buffered output goes unflushed and cleanup does
not run. Return an error from `main` instead.

Test code is exempt from most of these via `clippy.toml` — an `unwrap` in a test
is an assertion, and a panic is how a test reports failure.

## 3. Silence a lint at the site, with a reason

```rust
#[expect(
    clippy::indexing_slicing,
    reason = "the slice is a fixed-size array from a const generic; \
              the index is checked against N above"
)]
```

Use `#[expect]`, never `#[allow]` — `clippy::allow_attributes` and
`clippy::allow_attributes_without_reason` are on. `#[expect]` fails the build
once the lint stops firing, so a justification cannot outlive the code it
justified.

A reason that restates the lint name ("reason = "we need to index here"") is not
a reason. Say what makes the operation safe.

## 4. Commits

[Conventional Commits](https://www.conventionalcommits.org/) are enforced by
`cog check` locally and in CI. The changelog is generated from them
(`cliff.toml`), so the subject line is user-facing text; `chore`, `ci` and
`style` commits stay out of it, and `!` or a `BREAKING CHANGE` footer lists a
commit first:

```
feat(parser): accept bare keys in section headers
fix: reject a trailing separator instead of panicking
docs: explain why exit is denied
build(deps): bump serde from 1.0.200 to 1.0.201
```

## 5. Before you claim a change is done

Run `just checks`. It is the same nine steps CI runs. Reporting "done" on a
change that has not passed it is the one thing that wastes the most time here.

If a check fails for reasons unrelated to your change, say so explicitly rather
than working around it — a broken check that everyone routes around stops
protecting anything.
