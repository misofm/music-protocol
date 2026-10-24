// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::release_e2e_tests;

use std::unit_test::{assert_eq, destroy};
use sui::event;
use sui::test_scenario;
use miso_music::composition::{Self, Composition};
use miso_music::recording::{Self, Recording};
use miso_music::release::{Self, Release};
use miso_music::test_helpers::{CompositionShare, RecordingShare};

const SONGWRITER: address = @0xA1;
const ARTIST: address = @0xA2;
const CURATOR: address = @0xA3;
const READER: address = @0xBEEF;

#[test]
fun anyone_releases_a_published_recording() {
    let mut scenario = test_scenario::begin(SONGWRITER);
    let (comp, comp_cap) = composition::new_for_testing<CompositionShare>(scenario.ctx());
    comp.publish(&comp_cap);
    destroy(comp_cap);

    scenario.next_tx(ARTIST);
    let comp = scenario.take_shared<Composition<CompositionShare>>();
    let composition_id = object::id(&comp);
    let (rec, rec_cap) = recording::new_for_testing<RecordingShare>(
        composition_id,
        scenario.ctx(),
    );
    rec.publish(&rec_cap);
    let mut recording_events =
        event::events_by_type<recording::RecordingPublishedEvent<RecordingShare>>();
    let (rec_event_recording_id, rec_event_composition_id, _) =
        recording::recording_published_event_fields(recording_events.pop_back());
    test_scenario::return_shared(comp);

    scenario.next_tx(CURATOR);
    let rec = scenario.take_shared<Recording<RecordingShare>>();
    let recording_id = object::id(&rec);
    let (rel, rel_cap) = release::new(vector[release::new_track(&rec)], scenario.ctx());
    let release_id = object::id(&rel);
    test_scenario::return_shared(rec);
    assert_eq!(event::events_by_type<release::ReleasePublishedEvent>().length(), 0);

    rel.publish(&rel_cap);

    let mut published_events = event::events_by_type<release::ReleasePublishedEvent>();
    assert_eq!(published_events.length(), 1);
    let (event_release_id, event_admin_cap_id, event_tracks) =
        release::release_published_event_fields(published_events.pop_back());
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_admin_cap_id, object::id(&rel_cap));
    assert_eq!(event_tracks.length(), 1);
    assert_eq!(event_tracks[0].recording_id(), recording_id);
    assert_eq!(event_tracks[0].recording_id(), rec_event_recording_id);
    assert_eq!(rec_event_composition_id, composition_id);
    destroy(rel_cap);

    scenario.next_tx(READER);
    let rel = scenario.take_shared<Release>();
    assert_eq!(object::id(&rel), release_id);
    assert_eq!(rel.tracks()[0].recording_id(), recording_id);
    test_scenario::return_shared(rel);

    destroy(rec_cap);
    scenario.end();
}
