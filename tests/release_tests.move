// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::release_tests;

use std::unit_test::{assert_eq, destroy};
use sui::event;
use miso_music::recording;
use miso_music::release::{Self, ReleaseTrack};
use miso_music::test_helpers::{Self, RecordingShare};

fun fake_recording_ids(track_count: u64, ctx: &mut TxContext): vector<ID> {
    vector::tabulate!(track_count, |_| test_helpers::fake_id(ctx))
}

fun release_tracks(recording_ids: vector<ID>): vector<ReleaseTrack> {
    recording_ids.map!(|recording_id| release::new_release_track_for_testing(recording_id))
}

// === Creation Validation ===

#[test, expected_failure(abort_code = release::ENoTracks)]
fun new_without_tracks_aborts() {
    let ctx = &mut tx_context::dummy();
    let (release, cap) = release::new(vector[], ctx);
    destroy(release);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::EDuplicateRecording)]
fun new_with_duplicate_recording_aborts() {
    let ctx = &mut tx_context::dummy();
    let (a, b) = (test_helpers::fake_id(ctx), test_helpers::fake_id(ctx));
    let (release, cap) = release::new(release_tracks(vector[a, b, a]), ctx);
    destroy(release);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::ETooManyTracks)]
fun new_above_max_tracks_aborts() {
    let ctx = &mut tx_context::dummy();
    let recording_ids = fake_recording_ids((release::max_tracks_for_testing() as u64) + 1, ctx);
    let (release, cap) = release::new(release_tracks(recording_ids), ctx);
    destroy(release);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::ETooManyTracks)]
fun new_above_max_tracks_with_duplicate_aborts_too_many() {
    let ctx = &mut tx_context::dummy();
    let mut recording_ids = fake_recording_ids((release::max_tracks_for_testing() as u64), ctx);
    let repeated = recording_ids[0];
    recording_ids.push_back(repeated);
    let (release, cap) = release::new(release_tracks(recording_ids), ctx);
    destroy(release);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::EDuplicateRecording)]
fun new_at_max_tracks_with_duplicate_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut recording_ids = fake_recording_ids((release::max_tracks_for_testing() as u64) - 1, ctx);
    let repeated = recording_ids[200];
    recording_ids.push_back(repeated);
    let (release, cap) = release::new(release_tracks(recording_ids), ctx);
    destroy(release);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::EDuplicateRecording)]
fun new_with_adjacent_duplicate_aborts() {
    let ctx = &mut tx_context::dummy();
    let a = test_helpers::fake_id(ctx);
    let (release, cap) = release::new(release_tracks(vector[a, a]), ctx);
    destroy(release);
    destroy(cap);
}

#[test]
fun new_at_max_tracks_keeps_order() {
    let ctx = &mut tx_context::dummy();
    let recording_ids = fake_recording_ids((release::max_tracks_for_testing() as u64), ctx);
    let (release, cap) = release::new(release_tracks(recording_ids), ctx);
    assert_eq!(*release.recording_ids(), recording_ids);
    destroy(release);
    destroy(cap);
}

#[test]
fun two_releases_of_the_same_tracks_are_distinct() {
    let ctx = &mut tx_context::dummy();
    let recording_ids = fake_recording_ids(2, ctx);
    let (release_a, cap_a) = release::new(release_tracks(recording_ids), ctx);
    let (release_b, cap_b) = release::new(release_tracks(recording_ids), ctx);
    assert!(object::id(&release_a) != object::id(&release_b));
    assert_eq!(*release_a.recording_ids(), *release_b.recording_ids());
    destroy(release_a);
    destroy(cap_a);
    destroy(release_b);
    destroy(cap_b);
}

// === Tracks ===

#[test]
fun new_release_track_records_the_recording() {
    let ctx = &mut tx_context::dummy();
    let (recording, recording_cap) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    let track = release::new_release_track(&recording);
    assert_eq!(track.recording_id(), object::id(&recording));
    destroy(recording);
    destroy(recording_cap);
}

#[test]
fun anyone_can_release_recordings_owned_by_others() {
    let ctx = &mut tx_context::dummy();
    let (recording_a, recording_cap_a) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    let (recording_b, recording_cap_b) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    let (release, cap) = release::new(
        vector[release::new_release_track(&recording_b), release::new_release_track(&recording_a)],
        ctx,
    );
    assert_eq!(release.recording_ids()[0], object::id(&recording_b));
    assert_eq!(release.recording_ids()[1], object::id(&recording_a));
    destroy(release);
    destroy(cap);
    destroy(recording_a);
    destroy(recording_cap_a);
    destroy(recording_b);
    destroy(recording_cap_b);
}

// === Views ===

#[test]
fun release_views_reflect_the_new_release() {
    let ctx = &mut tx_context::dummy();
    let recording_id = test_helpers::fake_id(ctx);
    let tracks = vector[release::new_release_track_for_testing(recording_id)];
    let (release, cap) = release::new(tracks, ctx);

    assert_eq!(release.recording_ids().length(), 1);
    assert_eq!(release.recording_ids()[0], recording_id);
    assert_eq!(cap.release_id(), object::id(&release));
    assert_eq!(release.uid().to_inner(), object::id(&release));

    destroy(release);
    destroy(cap);
}

// === Events ===

#[test]
fun release_published_event_at_max_tracks() {
    let ctx = &mut tx_context::dummy();
    let recording_ids = fake_recording_ids((release::max_tracks_for_testing() as u64), ctx);
    let (release, cap) = release::new(release_tracks(recording_ids), ctx);
    let release_id = object::id(&release);

    assert_eq!(event::events_by_type<release::ReleasePublishedEvent>().length(), 0);

    release.publish(&cap);
    let cap_id = object::id(&cap);
    destroy(cap);
    let mut published_events = event::events_by_type<release::ReleasePublishedEvent>();
    assert_eq!(published_events.length(), 1);
    let (event_release_id, event_release_admin_cap_id, event_recording_ids) =
        release::release_published_event_fields(published_events.pop_back());
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_release_admin_cap_id, cap_id);
    assert_eq!(event_recording_ids, recording_ids);
}

// === Authorization ===

#[test]
fun authorize_accepts_the_release_cap() {
    let ctx = &mut tx_context::dummy();
    let (release, cap) = release::new(release_tracks(fake_recording_ids(1, ctx)), ctx);
    release.authorize(&cap);
    destroy(release);
    destroy(cap);
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun authorize_rejects_another_release_cap() {
    let ctx = &mut tx_context::dummy();
    let (release, cap) = release::new(release_tracks(fake_recording_ids(1, ctx)), ctx);
    let (other_release, other_cap) = release::new(release_tracks(fake_recording_ids(1, ctx)), ctx);
    release.authorize(&other_cap);
    destroy(release);
    destroy(cap);
    destroy(other_release);
    destroy(other_cap);
}
