//! Command-line entry point for `{{project-name}}`.
//!
{% if project_kind == "both" -%}
//! Everything worth testing lives in the library half of this crate
//! (`src/lib.rs`); this file is the thin shell that turns process
//! arguments into calls on it. Keeping the shell thin is what lets the
//! logic be tested without spawning a process.
{% else -%}
//! The lint policy in `Cargo.toml` denies the operations that can end
//! the process without returning an error: `a + b`, `v[i]`,
//! `.unwrap()`, `.expect()`, `panic!` and `as` compile, but clippy
//! rejects them here (`just clippy`, and CI).
//! Each has a total counterpart -- [`u64::checked_add`], [`slice::get`],
//! `ok_or`/`?`, [`u64::try_from`] -- and reaching for it is the point.
//!
//! When the answer really is "this cannot happen", say so at the site
//! with `#[expect(lint, reason = "...")]` rather than `#[allow]`. An
//! `expect` that stops being true becomes a compile error.
{% endif -%}
{% if project_kind == "both" %}
use {{crate_name}}::saturating_total;
{% endif %}
/// Process entry point.
///
/// Returning `()` is deliberate for now: as soon as this function can
/// fail, change it to `fn main() -> Result<(), Box<dyn std::error::Error>>`
/// so failures print and set a non-zero exit code without `process::exit`
/// (`clippy::exit` is denied, because an `exit` in the middle of a call
/// stack skips every `Drop` on the way out).
fn main() {
{%- if project_kind == "both" %}
    let total = saturating_total(2, 3);
    println!("{{project-name}}: 2 + 3 = {total}");
{%- else %}
    println!("Hello from {{project-name}}!");
{%- endif %}
}
