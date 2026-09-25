//! {{description}}
//!
//! # Working in this crate
//!
//! The lint policy in `Cargo.toml` is stricter than the Rust default in
//! one way that shows up immediately: the operations that can end the
//! process without returning an error are denied, not warned about.
//! `a + b`, `v[i]`, `&s[a..b]`, `.unwrap()`, `.expect()`, `panic!` and
//! `as` will not compile here.
//!
//! Each has a total counterpart -- [`u64::checked_add`],
//! [`slice::get`], [`str::get`], `ok_or`/`?`, and [`u64::try_from`] --
//! and reaching for it is the point: the compiler is asking what should
//! happen in the case you had not yet considered.
//!
//! When the answer really is "this cannot happen", say so at the site
//! with `#[expect(lint, reason = "...")]` rather than `#[allow]`. An
//! `expect` that stops being true becomes a compile error, so the
//! justification cannot outlive the code it justified.

/// Adds two counts, saturating at [`u64::MAX`] rather than overflowing.
///
/// `clippy::arithmetic_side_effects` is denied crate-wide, so plain
/// `left + right` would not compile: in release builds it wraps
/// silently, and in debug builds it panics. Naming the overflow
/// behaviour makes it reviewable.
///
/// # Examples
///
/// ```
/// use {{crate_name}}::saturating_total;
///
/// assert_eq!(saturating_total(2, 3), 5);
/// assert_eq!(saturating_total(u64::MAX, 1), u64::MAX);
/// ```
#[must_use]
pub const fn saturating_total(left: u64, right: u64) -> u64 {
    left.saturating_add(right)
}

#[cfg(test)]
mod tests {
    use super::saturating_total;

    /// The ordinary case, pinned so the saturating variant below is
    /// read as a boundary rather than as the whole behaviour.
    #[test]
    fn totals_two_small_counts() {
        assert_eq!(saturating_total(2, 3), 5);
    }

    /// The reason this function exists: at the top of the range it
    /// clamps instead of wrapping to a small number, which is what a
    /// bare `+` would do in a release build.
    #[test]
    fn clamps_at_max_instead_of_wrapping() {
        assert_eq!(saturating_total(u64::MAX, 1), u64::MAX);
        assert_eq!(saturating_total(u64::MAX, u64::MAX), u64::MAX);
    }
}
