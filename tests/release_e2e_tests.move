// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::release_e2e_tests;

use std::unit_test::{assert_eq, destroy};
use sui::event;
use sui::test_scenario;
use miso_music::composition::{Self, Composition};
use miso_music::recording::{Self, Recording};
use miso_music::release::{Self, Release, ReleaseRegistry};
use miso_music::test_helpers::{Self, CompositionShare, RecordingShare};

const SONGWRITER: address = @0xA1;
const ARTIST: address = @0xA2;
const LABEL: address = @0xA3;
const READER: address = @0xBEEF;

const SALT: vector<u8> = x"2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a";

#[test]
fun init_creates_shared_registry() {
    let mut scenario = test_scenario::begin(SONGWRITER);
    release::init_for_testing(scenario.ctx());

    scenario.next_tx(READER);
    let registry = scenario.take_shared<ReleaseRegistry>();
    test_scenario::return_shared(registry);
    scenario.end();
}

#[test]
fun full_track_release_flow_publishes_at_derived_id() {
    let mut scenario = test_scenario::begin(SONGWRITER);
    release::init_for_testing(scenario.ctx());

    // === Tx 1 (SONGWRITER): create and publish the composition ===
    scenario.next_tx(SONGWRITER);
    let (comp, comp_cap) = composition::new_for_testing<CompositionShare>(scenario.ctx());
    comp.publish(&comp_cap); // shares the composition
    destroy(comp_cap);

    // === Tx 2 (ARTIST): create and publish a recording of it ===
    scenario.next_tx(ARTIST);
    let comp = scenario.take_shared<Composition<CompositionShare>>();
    let (rec, rec_cap) = recording::new_for_testing<RecordingShare>(
        object::id(&comp),
        scenario.ctx(),
    );
    rec.publish(&rec_cap); // shares the recording
    let mut recording_events =
        event::events_by_type<recording::RecordingPublishedEvent<RecordingShare>>();
    let (rec_event_recording_id, rec_event_composition_id, rec_event_admin_cap_id) =
        recording::recording_published_event_fields(recording_events.pop_back());
    assert_eq!(rec_event_admin_cap_id, object::id(&rec_cap));
    test_scenario::return_shared(comp);

    // === Tx 3 (ARTIST): consent to the predicted release id via release::consent ===
    scenario.next_tx(ARTIST);
    let comp = scenario.take_shared<Composition<CompositionShare>>();
    let rec = scenario.take_shared<Recording<RecordingShare>>();
    let registry = scenario.take_shared<ReleaseRegistry>();
    let recording_id = object::id(&rec);
    let composition_id = object::id(&comp);
    let predicted_release_id = registry.derive_address(vector[recording_id], SALT).to_id();
    let t = release::consent(&rec, &rec_cap, predicted_release_id);
    test_scenario::return_shared(comp);
    test_scenario::return_shared(rec);
    test_scenario::return_shared(registry);

    // === Tx 4 (LABEL): assemble and publish the release ===
    scenario.next_tx(LABEL);
    let mut registry = scenario.take_shared<ReleaseRegistry>();
    let (rel, rel_cap) = registry.new(vector[t], SALT);
    assert_eq!(object::id(&rel), predicted_release_id);
    assert_eq!(event::events_by_type<release::ReleasePublishedEvent>().length(), 0);

    rel.publish(&rel_cap); // shares and emits the release event

    let mut published_events = event::events_by_type<release::ReleasePublishedEvent>();
    assert_eq!(published_events.length(), 1);
    let (event_release_id, event_admin_cap_id, event_recording_ids, event_salt) =
        release::release_published_event_fields(published_events.pop_back());
    assert_eq!(event_release_id, predicted_release_id);
    assert_eq!(event_admin_cap_id, object::id(&rel_cap));
    assert_eq!(event_recording_ids, vector[recording_id]);
    assert_eq!(event_salt, SALT);
    // The event carries no composition ids: joining each recording id to that
    // recording's `RecordingPublishedEvent` yields it.
    assert_eq!(event_recording_ids[0], rec_event_recording_id);
    assert_eq!(rec_event_composition_id, composition_id);
    assert_eq!(registry.derive_address(event_recording_ids, event_salt).to_id(), event_release_id);

    destroy(rel_cap);
    test_scenario::return_shared(registry);

    // === Tx 5 (READER): the published release is publicly consistent ===
    scenario.next_tx(READER);
    let rel = scenario.take_shared<Release>();
    assert!(rel.is_published_state());
    assert_eq!(object::id(&rel), predicted_release_id);
    assert_eq!(*rel.recording_ids(), vector[recording_id]);
    test_scenario::return_shared(rel);

    destroy(rec_cap);
    scenario.end();
}

#[test, expected_failure(abort_code = release::EUnauthorizedAssignment)]
fun new_aborts_when_consent_targets_a_different_release() {
    let mut scenario = test_scenario::begin(SONGWRITER);
    release::init_for_testing(scenario.ctx());

    // One actor for brevity — the binding doesn't depend on senders.
    scenario.next_tx(SONGWRITER);
    let (_comp, _comp_cap) = composition::new_for_testing<CompositionShare>(scenario.ctx());
    let (rec, rec_cap) = recording::new_for_testing<RecordingShare>(
        object::id(&_comp),
        scenario.ctx(),
    );

    scenario.next_tx(SONGWRITER);
    // Track consented to the release that salt 1 would produce...
    let registry = scenario.take_shared<ReleaseRegistry>();
    let wrong_release_id = registry
        .derive_address(vector[object::id(&rec)], test_helpers::salt(1))
        .to_id();
    let t = release::consent(&rec, &rec_cap, wrong_release_id);
    test_scenario::return_shared(registry);

    scenario.next_tx(SONGWRITER);
    // ...but the release is created with salt 2: different derived id.
    let mut registry = scenario.take_shared<ReleaseRegistry>();
    let (rel, rel_cap) = registry.new(vector[t], test_helpers::salt(2));
    destroy(rel);
    destroy(rel_cap); // new must reject without calling publish

    // Unreachable, but the compiler requires all non-drop values consumed.
    abort
}
