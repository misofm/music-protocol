// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// `release::new` validation and `release::consent` boundary checks. None touch
/// object ownership; publish and wrong-cap flows live in `post_publish_tests`
/// and `release_e2e_tests`.
#[test_only]
module miso_music::release_tests;

use std::unit_test::{assert_eq, destroy};
use sui::derived_object;
use miso_music::composition;
use miso_music::recording;
use miso_music::release;
use miso_music::test_helpers::{Self, CompositionShare, RecordingShare};

fun test_tracks(track_count: u64, ctx: &mut TxContext): vector<release::ReleaseConsent> {
    vector::tabulate!(track_count, |_index| release::consent_for_testing(
        test_helpers::fake_id(ctx),
        test_helpers::fake_id(ctx),
    ))
}

fun composition_and_recording(
    ctx: &mut TxContext,
): (
    composition::Composition<CompositionShare>,
    composition::CompositionAdminCap<CompositionShare>,
    recording::Recording<RecordingShare>,
    recording::RecordingAdminCap<RecordingShare>,
) {
    let (comp, comp_cap) = composition::new_for_testing(ctx);
    let (rec, rec_cap) = recording::new_for_testing(object::id(&comp), ctx);
    (comp, comp_cap, rec, rec_cap)
}

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

#[test, expected_failure(abort_code = release::ETooManyTracks)]
fun new_above_max_tracks_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut registry = release::new_registry_for_testing(ctx);
    let tracks = test_tracks(release::max_tracks() + 1, ctx);
    let (rel, cap) = registry.new(tracks, test_helpers::salt(0));
    destroy(rel);
    destroy(cap);
    destroy(registry);
}

/// The track-count check runs before the duplicate check.
#[test, expected_failure(abort_code = release::ETooManyTracks)]
fun new_above_max_tracks_with_duplicate_aborts_too_many() {
    let ctx = &mut tx_context::dummy();
    let mut registry = release::new_registry_for_testing(ctx);
    let mut tracks = test_tracks(release::max_tracks(), ctx);
    let repeated = tracks[0].recording_id();
    tracks.push_back(release::consent_for_testing(repeated, test_helpers::fake_id(ctx)));
    let (rel, cap) = registry.new(tracks, test_helpers::salt(0));
    destroy(rel);
    destroy(cap);
    destroy(registry);
}

/// A recording may fill only one slot, wherever the repeat falls.
#[test, expected_failure(abort_code = release::EDuplicateRecording)]
fun new_with_duplicate_recording_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut registry = release::new_registry_for_testing(ctx);
    let (a, b) = (test_helpers::fake_id(ctx), test_helpers::fake_id(ctx));
    let release_id = registry.derive_address(vector[a, b, a], test_helpers::salt(0)).to_id();
    let (rel, cap) = registry.new(
        vector[
            release::consent_for_testing(a, release_id),
            release::consent_for_testing(b, release_id),
            release::consent_for_testing(a, release_id),
        ],
        test_helpers::salt(0),
    );
    destroy(rel);
    destroy(cap);
    destroy(registry);
}

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

#[test, expected_failure(abort_code = release::EDuplicateRecording)]
fun new_with_adjacent_duplicate_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut registry = release::new_registry_for_testing(ctx);
    let a = test_helpers::fake_id(ctx);
    let release_id = registry.derive_address(vector[a, a], test_helpers::salt(0)).to_id();
    let (rel, cap) = registry.new(
        vector[
            release::consent_for_testing(a, release_id),
            release::consent_for_testing(a, release_id),
        ],
        test_helpers::salt(0),
    );
    destroy(rel);
    destroy(cap);
    destroy(registry);
}

#[test, expected_failure(abort_code = release::EUnauthorizedAssignment)]
fun new_with_later_mismatched_consent_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut registry = release::new_registry_for_testing(ctx);
    let (a, b) = (test_helpers::fake_id(ctx), test_helpers::fake_id(ctx));
    let release_id = registry.derive_address(vector[a, b], test_helpers::salt(0)).to_id();
    let (rel, cap) = registry.new(
        vector[
            release::consent_for_testing(a, release_id),
            release::consent_for_testing(b, test_helpers::fake_id(ctx)),
        ],
        test_helpers::salt(0),
    );
    destroy(rel);
    destroy(cap);
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
    assert_eq!(cap.release_id(), object::id(&rel));

    destroy(rel);
    destroy(cap);
}

// === release::consent ===

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
