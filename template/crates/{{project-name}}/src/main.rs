//! Command-line entry point for `{{project-name}}`.
//!
//! Everything worth testing lives in `{{project-name}}-core`; this file is
//! the thin shell that turns process arguments into calls on it. Keeping
//! the shell thin is what lets the logic be tested without spawning a
//! process.

use {{crate_name}}_core::saturating_total;

/// Process entry point.
///
/// Returning `()` is deliberate for now: as soon as this function can
/// fail, change it to `fn main() -> Result<(), Box<dyn std::error::Error>>`
/// so failures print and set a non-zero exit code without `process::exit`
/// (`clippy::exit` is denied, because an `exit` in the middle of a call
/// stack skips every `Drop` on the way out).
fn main() {
    let total = saturating_total(2, 3);
    println!("{{project-name}}: 2 + 3 = {total}");
}
