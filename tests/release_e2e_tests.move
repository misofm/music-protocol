// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::release_e2e_tests;

use miso_music::{
    composition::{Self, Composition},
    recording::{Self, Recording},
    release::{Self, Release},
    test_helpers::{CompositionShare, RecordingShare}
};
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario};

const SONGWRITER: address = @0xA1;
const ARTIST: address = @0xA2;
const CURATOR: address = @0xA3;
const READER: address = @0xBEEF;

#[test]
fun anyone_releases_a_published_recording() {
    let mut scenario = test_scenario::begin(SONGWRITER);
    let (composition, composition_cap) = composition::new_for_testing<
        CompositionShare,
    >(scenario.ctx());
    composition.publish(&composition_cap);
    destroy(composition_cap);
    scenario.next_tx(ARTIST);
    let composition = scenario.take_shared<Composition<CompositionShare>>();
    let composition_id = object::id(&composition);
    let (recording, recording_cap) = recording::new_for_testing<RecordingShare>(
        composition_id,
        scenario.ctx(),
    );
    recording.publish(&recording_cap);
    let mut recording_events = event::events_by_type<
        recording::RecordingPublishedEvent<RecordingShare>,
    >();
    let (
        event_recording_id,
        _,
        event_composition_id,
    ) = recording::recording_published_event_fields_for_testing(&recording_events.pop_back());
    test_scenario::return_shared(composition);
    scenario.next_tx(CURATOR);
    let recording = scenario.take_shared<Recording<RecordingShare>>();
    let recording_id = object::id(&recording);
    let (release, release_cap) = release::new(
        vector[release::new_release_track(&recording)],
        scenario.ctx(),
    );
    let release_id = object::id(&release);
    test_scenario::return_shared(recording);
    assert_eq!(event::events_by_type<release::ReleasePublishedEvent>().length(), 0);
    release.publish(&release_cap);
    let mut published_events = event::events_by_type<release::ReleasePublishedEvent>();
    assert_eq!(published_events.length(), 1);
    let (
        event_release_id,
        event_release_admin_cap_id,
        event_recording_ids,
    ) = release::release_published_event_fields_for_testing(&published_events.pop_back());
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_release_admin_cap_id, object::id(&release_cap));
    assert_eq!(event_recording_ids, vector[recording_id]);
    assert_eq!(event_recording_ids, vector[event_recording_id]);
    assert_eq!(event_composition_id, composition_id);
    destroy(release_cap);
    scenario.next_tx(READER);
    let release = scenario.take_shared<Release>();
    assert_eq!(object::id(&release), release_id);
    assert_eq!(release.recording_ids()[0], recording_id);
    test_scenario::return_shared(release);
    destroy(recording_cap);
    scenario.end();
}
