/// `release::new` validation and `release::consent` boundary checks. None touch
/// object ownership; publish and wrong-cap flows live in `post_publish_tests`
/// and `release_e2e_tests`.
#[test_only]
module musicos::release_tests;

use std::unit_test::{assert_eq, destroy};
use sui::derived_object;
use musicos::composition;
use musicos::recording;
use musicos::release;
use musicos::test_helpers::{Self, CompositionShare, RecordingShare};

/// Helper to create an ordered tracklist of n tracks.
fun test_tracks(track_count: u64, ctx: &mut TxContext): vector<release::ReleaseConsent> {
    vector::tabulate!(track_count, |_index| release::consent_for_testing(
        test_helpers::fake_id(ctx),
        test_helpers::fake_id(ctx),
    ))
}

/// Helper: a composition and a recording of it, with their admin caps.
fun composition_and_recording(
    ctx: &mut TxContext,
): (
    composition::Composition<CompositionShare>,
    composition::CompositionAdminCap<CompositionShare>,
    recording::Recording<RecordingShare>,
    recording::RecordingAdminCap<RecordingShare>,
) {
    let (comp, comp_cap) =
        composition::new_for_testing(ctx);
    let (rec, rec_cap) =
        recording::new_for_testing(object::id(&comp), ctx);
    (comp, comp_cap, rec, rec_cap)
}

/// Helper to create a minimal release.
fun test_release(ctx: &mut TxContext): (release::Release, release::ReleaseAdminCap) {
    release::new_for_testing(test_tracks(1, ctx), ctx)
}

// === Creation Validation ===

#[test, expected_failure(abort_code = release::ENoTracks)]
fun new_without_tracks_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut registry = release::new_registry_for_testing(ctx);
    let (rel, cap) = registry.new(vector[], test_helpers::salt(0));
    destroy(rel);
    destroy(cap);
    destroy(registry);
}

/// The same digest (recording ids + salt) can only ever be claimed
/// once under the same canonical registry.
#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun duplicate_digest_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut registry = release::new_registry_for_testing(ctx);
    let rec_id = test_helpers::fake_id(ctx);
    let rel_id = registry.derive_address(vector[rec_id], test_helpers::salt(7)).to_id();

    let (rel1, cap1) = registry.new(
        vector[release::consent_for_testing(rec_id, rel_id)],
        test_helpers::salt(7),
    );
    // Identical recording ids and salt: identical digest.
    let (rel2, cap2) = registry.new(
        vector[release::consent_for_testing(rec_id, rel_id)],
        test_helpers::salt(7),
    );
    destroy(rel1);
    destroy(cap1);
    destroy(rel2);
    destroy(cap2);
    destroy(registry);
}

// === Authorization ===

// The wrong-cap `uid_mut` abort (`EUnauthorized`) is exercised cross-actor in
// `post_publish_tests::release_uid_mut_wrong_cap_aborts`.

// === Views ===

#[test]
fun release_views_reflect_initialized_release() {
    let ctx = &mut tx_context::dummy();
    let (rel, cap) = test_release(ctx);

    assert!(rel.is_initialized_state());
    assert!(!rel.is_published_state());
    assert_eq!(rel.recording_ids().length(), 1);

    destroy(rel);
    destroy(cap);
}

// === release::consent ===

/// `release::consent` carries the target release id it was called with and
/// reads the recording id off the `&Recording` argument.
#[test]
fun consent_records_release_and_recording() {
    let ctx = &mut tx_context::dummy();
    let (comp, comp_cap, rec, rec_cap) = composition_and_recording(ctx);
    let target_release_id = test_helpers::fake_id(ctx);

    let consent = release::consent(&rec, &rec_cap, target_release_id);

    assert_eq!(consent.recording_id(), object::id(&rec));
    assert_eq!(consent.release_id(), target_release_id);

    destroy(consent);
    destroy(comp);
    destroy(comp_cap);
    destroy(rec);
    destroy(rec_cap);
}
