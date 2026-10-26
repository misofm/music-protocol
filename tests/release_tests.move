// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::release_tests;

use std::unit_test::{assert_eq, destroy};
use miso_music::recording;
use miso_music::release::{Self, Release, ReleaseTrack};
use miso_music::test_helpers::{Self, RecordingShare};

fun test_recording_ids(track_count: u64, ctx: &mut TxContext): vector<ID> {
    vector::tabulate!(track_count, |_| test_helpers::fake_id(ctx))
}

fun test_tracks(recording_ids: vector<ID>): vector<ReleaseTrack> {
    recording_ids.map!(|recording_id| release::release_track_for_testing(recording_id))
}

fun track_recording_ids(rel: &Release): vector<ID> {
    rel.tracks().map_ref!(|track| track.recording_id())
}

// === Creation Validation ===

#[test, expected_failure(abort_code = release::ENoTracks)]
fun new_without_tracks_aborts() {
    let ctx = &mut tx_context::dummy();
    let (rel, cap) = release::new(vector[], ctx);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::EDuplicateRecording)]
fun new_with_duplicate_recording_aborts() {
    let ctx = &mut tx_context::dummy();
    let (a, b) = (test_helpers::fake_id(ctx), test_helpers::fake_id(ctx));
    let (rel, cap) = release::new(test_tracks(vector[a, b, a]), ctx);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::ETooManyTracks)]
fun new_above_max_tracks_aborts() {
    let ctx = &mut tx_context::dummy();
    let recording_ids = test_recording_ids(release::max_tracks() + 1, ctx);
    let (rel, cap) = release::new(test_tracks(recording_ids), ctx);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::ETooManyTracks)]
fun new_above_max_tracks_with_duplicate_aborts_too_many() {
    let ctx = &mut tx_context::dummy();
    let mut recording_ids = test_recording_ids(release::max_tracks(), ctx);
    let repeated = recording_ids[0];
    recording_ids.push_back(repeated);
    let (rel, cap) = release::new(test_tracks(recording_ids), ctx);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::EDuplicateRecording)]
fun new_at_max_tracks_with_duplicate_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut recording_ids = test_recording_ids(release::max_tracks() - 1, ctx);
    let repeated = recording_ids[200];
    recording_ids.push_back(repeated);
    let (rel, cap) = release::new(test_tracks(recording_ids), ctx);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::EDuplicateRecording)]
fun new_with_adjacent_duplicate_aborts() {
    let ctx = &mut tx_context::dummy();
    let a = test_helpers::fake_id(ctx);
    let (rel, cap) = release::new(test_tracks(vector[a, a]), ctx);
    destroy(rel);
    destroy(cap);
}

#[test]
fun new_at_max_tracks_keeps_order() {
    let ctx = &mut tx_context::dummy();
    let recording_ids = test_recording_ids(release::max_tracks(), ctx);
    let (rel, cap) = release::new(test_tracks(recording_ids), ctx);
    assert_eq!(track_recording_ids(&rel), recording_ids);
    destroy(rel);
    destroy(cap);
}

#[test]
fun two_releases_of_the_same_tracks_are_distinct() {
    let ctx = &mut tx_context::dummy();
    let recording_ids = test_recording_ids(2, ctx);
    let (rel_a, cap_a) = release::new(test_tracks(recording_ids), ctx);
    let (rel_b, cap_b) = release::new(test_tracks(recording_ids), ctx);
    assert!(object::id(&rel_a) != object::id(&rel_b));
    assert_eq!(track_recording_ids(&rel_a), track_recording_ids(&rel_b));
    destroy(rel_a);
    destroy(cap_a);
    destroy(rel_b);
    destroy(cap_b);
}

// === Tracks ===

#[test]
fun new_release_track_records_the_recording() {
    let ctx = &mut tx_context::dummy();
    let (rec, rec_cap) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    let track = release::new_release_track(&rec);
    assert_eq!(track.recording_id(), object::id(&rec));
    destroy(rec);
    destroy(rec_cap);
}

#[test]
fun anyone_can_release_recordings_owned_by_others() {
    let ctx = &mut tx_context::dummy();
    let (rec_a, rec_cap_a) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    let (rec_b, rec_cap_b) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    let (rel, cap) = release::new(
        vector[release::new_release_track(&rec_b), release::new_release_track(&rec_a)],
        ctx,
    );
    assert_eq!(rel.tracks()[0].recording_id(), object::id(&rec_b));
    assert_eq!(rel.tracks()[1].recording_id(), object::id(&rec_a));
    destroy(rel);
    destroy(cap);
    destroy(rec_a);
    destroy(rec_cap_a);
    destroy(rec_b);
    destroy(rec_cap_b);
}

// === Views ===

#[test]
fun release_views_reflect_the_new_release() {
    let ctx = &mut tx_context::dummy();
    let recording_id = test_helpers::fake_id(ctx);
    let (rel, cap) = release::new(vector[release::release_track_for_testing(recording_id)], ctx);

    assert_eq!(rel.tracks().length(), 1);
    assert_eq!(rel.tracks()[0].recording_id(), recording_id);
    assert_eq!(cap.release_id(), object::id(&rel));
    assert_eq!(rel.uid().to_inner(), object::id(&rel));

    destroy(rel);
    destroy(cap);
}

// === Authorization ===

#[test]
fun authorize_accepts_the_release_cap() {
    let ctx = &mut tx_context::dummy();
    let (rel, cap) = release::new(test_tracks(test_recording_ids(1, ctx)), ctx);
    rel.authorize(&cap);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun authorize_rejects_another_release_cap() {
    let ctx = &mut tx_context::dummy();
    let (rel, cap) = release::new(test_tracks(test_recording_ids(1, ctx)), ctx);
    let (other_rel, other_cap) = release::new(test_tracks(test_recording_ids(1, ctx)), ctx);
    rel.authorize(&other_cap);
    destroy(rel);
    destroy(cap);
    destroy(other_rel);
    destroy(other_cap);
}
