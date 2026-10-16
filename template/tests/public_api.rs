//! Consumer-side validation of `{{project-name}}`'s public API.
//!
//! This is an integration-test crate, so it sees exactly what a
//! downstream dependent sees: `pub(crate)` items are invisible here.
//! That is the point -- the unit tests inside `src/lib.rs` can reach
//! internals and therefore cannot prove the published surface is
//! actually usable.

#![expect(
    clippy::tests_outside_test_module,
    reason = "integration-test crate: it has no cfg(test) module by design"
)]

use {{crate_name}}::saturating_total;

/// The exported function is reachable, callable, and re-exported under
/// the name the documentation promises.
///
/// A rename that only breaks downstream users -- and so passes every
/// unit test -- fails here instead.
#[test]
fn saturating_total_is_reachable_from_a_dependent() {
    assert_eq!(saturating_total(1, 1), 2);
}
