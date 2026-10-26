// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::kitchen_sink_tests;

use std::unit_test::{assert_eq, destroy};
use sui::event;
use miso_music::release;
use miso_music::test_helpers;

#[test]
fun release_published_event_at_max_tracks() {
    let ctx = &mut tx_context::dummy();
    let track_count = release::max_tracks();
    let recording_ids = vector::tabulate!(track_count, |_| test_helpers::fake_id(ctx));
    let tracks = recording_ids.map_ref!(|recording_id| release::release_track_for_testing(*recording_id));
    let (rel, rel_cap) = release::new(tracks, ctx);
    let release_id = object::id(&rel);

    assert_eq!(event::events_by_type<release::ReleasePublishedEvent>().length(), 0);

    rel.publish(&rel_cap);
    let rel_cap_id = object::id(&rel_cap);
    destroy(rel_cap);
    let mut published_events = event::events_by_type<release::ReleasePublishedEvent>();
    assert_eq!(published_events.length(), 1);
    let (event_release_id, event_admin_cap_id, event_recording_ids) =
        release::release_published_event_fields(published_events.pop_back());
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_admin_cap_id, rel_cap_id);
    assert_eq!(event_recording_ids, recording_ids);
}
