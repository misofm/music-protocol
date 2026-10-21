// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Structural stress test: a release at `MAX_TRACKS` builds and publishes
/// through the registry.
#[test_only]
module miso_music::kitchen_sink_tests;

use std::unit_test::{assert_eq, destroy};
use sui::event;
use miso_music::release;
use miso_music::test_helpers;

/// Publishing a release at `MAX_TRACKS` emits a single `ReleasePublishedEvent`
/// carrying the full tracklist in order.
#[test]
fun release_published_event_at_max_tracks() {
    let ctx = &mut tx_context::dummy();
    let mut registry = release::new_registry_for_testing(ctx);
    let track_count = release::max_tracks();
    let recording_ids = vector::tabulate!(track_count, |_| test_helpers::fake_id(ctx));

    let salt = test_helpers::salt(7);
    let predicted_release_id = registry.derive_address(recording_ids, salt).to_id();
    let tracks = vector::tabulate!(track_count, |index| release::consent_for_testing(
        recording_ids[index],
        predicted_release_id,
    ));
    let (rel, rel_cap) = registry.new(tracks, salt);

    assert_eq!(event::events_by_type<release::ReleasePublishedEvent>().length(), 0);

    rel.publish(&rel_cap);
    destroy(rel_cap);
    let mut published_events = event::events_by_type<release::ReleasePublishedEvent>();
    assert_eq!(published_events.length(), 1);
    let (event_release_id, event_recording_ids, event_salt) =
        release::release_published_event_fields(published_events.pop_back());
    assert_eq!(event_release_id, predicted_release_id);
    assert_eq!(event_recording_ids, recording_ids);
    assert_eq!(event_salt, salt);

    destroy(registry);
}
