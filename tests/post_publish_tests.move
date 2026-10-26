// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::post_publish_tests;

use std::unit_test::{assert_eq, destroy};
use sui::dynamic_field;
use sui::event;
use sui::test_scenario;
use miso_music::composition::{Self, Composition, CompositionPublishedEvent};
use miso_music::recording::{Self, Recording, RecordingPublishedEvent};
use miso_music::release::{Self, Release, ReleasePublishedEvent};
use miso_music::test_helpers::{Self, CompositionShare, RecordingShare};

const OWNER: address = @0xA1;
const STRANGER: address = @0x51;

fun publish_composition(
    scenario: &mut test_scenario::Scenario,
): composition::CompositionAdminCap<CompositionShare> {
    let ctx = scenario.ctx();
    let (comp, cap) = composition::new_for_testing<CompositionShare>(ctx);
    let comp_id = object::id(&comp);
    comp.publish(&cap);

    let mut events = event::events_by_type<CompositionPublishedEvent<CompositionShare>>();
    assert_eq!(events.length(), 1);
    let (event_comp_id, event_cap_id) =
        composition::composition_published_event_fields(events.pop_back());
    assert_eq!(event_comp_id, comp_id);
    assert_eq!(event_cap_id, object::id(&cap));

    cap
}

fun publish_recording(
    scenario: &mut test_scenario::Scenario,
): recording::RecordingAdminCap<RecordingShare> {
    let ctx = scenario.ctx();
    let composition_id = test_helpers::fake_id(ctx);
    let (rec, cap) = recording::new_for_testing<RecordingShare>(
        composition_id,
        ctx,
    );
    let rec_id = object::id(&rec);
    rec.publish(&cap);

    let mut events = event::events_by_type<RecordingPublishedEvent<RecordingShare>>();
    assert_eq!(events.length(), 1);
    let (event_rec_id, event_comp_id, event_cap_id) =
        recording::recording_published_event_fields(events.pop_back());
    assert_eq!(event_rec_id, rec_id);
    assert_eq!(event_cap_id, object::id(&cap));
    assert_eq!(event_comp_id, composition_id);

    cap
}

fun publish_release(scenario: &mut test_scenario::Scenario): (release::ReleaseAdminCap, ID) {
    let ctx = scenario.ctx();
    let recording_id = test_helpers::fake_id(ctx);
    let (rel, cap) = release::new_for_testing(vector[recording_id], ctx);
    let rel_id = object::id(&rel);
    rel.publish(&cap);

    let mut events = event::events_by_type<ReleasePublishedEvent>();
    assert!(!events.is_empty());
    let (event_rel_id, event_cap_id, tracks) =
        release::release_published_event_fields(events.pop_back());
    assert_eq!(event_rel_id, rel_id);
    assert_eq!(event_cap_id, object::id(&cap));
    assert_eq!(tracks, vector[release::release_track_for_testing(recording_id)]);

    (cap, rel_id)
}

// === Composition ===

#[test]
fun composition_uid_mut_works_after_publish() {
    let mut scenario = test_scenario::begin(OWNER);
    let cap = publish_composition(&mut scenario);

    scenario.next_tx(OWNER);
    let mut comp = scenario.take_shared<Composition<CompositionShare>>();
    dynamic_field::add(comp.uid_mut(&cap), b"extension", 42u64);
    assert!(dynamic_field::exists(comp.uid(), b"extension"));
    assert!(*dynamic_field::borrow<vector<u8>, u64>(comp.uid(), b"extension") == 42);
    test_scenario::return_shared(comp);

    destroy(cap);
    scenario.end();
}

// === Release ===

#[test]
fun release_publish_twice_emits_again() {
    let mut scenario = test_scenario::begin(OWNER);
    let (cap, rel_id) = publish_release(&mut scenario);

    scenario.next_tx(OWNER);
    let rel = scenario.take_shared<Release>();
    rel.publish(&cap);
    let mut events = event::events_by_type<ReleasePublishedEvent>();
    assert_eq!(events.length(), 1);
    let (event_rel_id, _, _) = release::release_published_event_fields(events.pop_back());
    assert_eq!(event_rel_id, rel_id);

    destroy(cap);
    scenario.end();
}

#[test]
fun recording_uid_mut_works_after_publish() {
    let mut scenario = test_scenario::begin(OWNER);
    let cap = publish_recording(&mut scenario);

    scenario.next_tx(OWNER);
    let mut rec = scenario.take_shared<Recording<RecordingShare>>();
    dynamic_field::add(rec.uid_mut(&cap), b"master", 7u64);
    assert!(dynamic_field::exists(rec.uid(), b"master"));
    test_scenario::return_shared(rec);

    destroy(cap);
    scenario.end();
}

#[test]
fun release_uid_mut_works_after_publish() {
    let mut scenario = test_scenario::begin(OWNER);
    let (cap, _rel_id) = publish_release(&mut scenario);

    scenario.next_tx(OWNER);
    let mut rel = scenario.take_shared<Release>();
    dynamic_field::add(rel.uid_mut(&cap), b"metadata", 9u64);
    assert!(dynamic_field::exists(rel.uid(), b"metadata"));
    test_scenario::return_shared(rel);

    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun release_publish_with_foreign_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (rel, cap) = release::new_for_testing(vector[test_helpers::fake_id(ctx)], ctx);
    let (other_rel, other_cap) = release::new_for_testing(vector[test_helpers::fake_id(ctx)], ctx);
    rel.publish(&other_cap);
    destroy(cap);
    destroy(other_rel);
    abort
}

#[test]
fun published_release_keeps_track_order() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let recording_ids = vector::tabulate!(3, |_| test_helpers::fake_id(ctx));
    let (rel, cap) = release::new_for_testing(recording_ids, ctx);
    rel.publish(&cap);

    scenario.next_tx(STRANGER);
    let rel = scenario.take_shared<Release>();
    assert_eq!(rel.tracks().map_ref!(|track| track.recording_id()), recording_ids);
    test_scenario::return_shared(rel);

    destroy(cap);
    scenario.end();
}

#[test]
fun release_dynamic_field_attached_before_publish_survives() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let (mut rel, cap) = release::new_for_testing(vector[test_helpers::fake_id(ctx)], ctx);
    dynamic_field::add(rel.uid_mut(&cap), b"cover", 5u64);
    rel.publish(&cap);

    scenario.next_tx(STRANGER);
    let rel = scenario.take_shared<Release>();
    assert_eq!(*dynamic_field::borrow<vector<u8>, u64>(rel.uid(), b"cover"), 5);
    test_scenario::return_shared(rel);

    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun release_uid_mut_wrong_cap_aborts() {
    let mut scenario = test_scenario::begin(OWNER);
    let (owner_cap, owner_rel_id) = publish_release(&mut scenario);

    scenario.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = publish_release(&mut scenario);

    scenario.next_tx(STRANGER);
    let mut owner_rel = test_scenario::take_shared_by_id<Release>(&scenario, owner_rel_id);
    let _uid = owner_rel.uid_mut(&stranger_cap);

    test_scenario::return_shared(owner_rel);
    destroy(owner_cap);
    destroy(stranger_cap);
    abort
}
