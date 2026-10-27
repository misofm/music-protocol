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
    let (composition, cap) = composition::new_for_testing<CompositionShare>(ctx);
    let composition_id = object::id(&composition);
    composition.publish(&cap);
    let mut events = event::events_by_type<CompositionPublishedEvent<CompositionShare>>();
    assert_eq!(events.length(), 1);
    let (event_composition_id, event_composition_admin_cap_id) =
        composition::composition_published_event_fields(&events.pop_back());
    assert_eq!(event_composition_id, composition_id);
    assert_eq!(event_composition_admin_cap_id, object::id(&cap));
    cap
}

fun publish_recording(
    scenario: &mut test_scenario::Scenario,
): recording::RecordingAdminCap<RecordingShare> {
    let ctx = scenario.ctx();
    let composition_id = test_helpers::fake_id(ctx);
    let (recording, cap) = recording::new_for_testing<RecordingShare>(
        composition_id,
        ctx,
    );
    let recording_id = object::id(&recording);
    recording.publish(&cap);
    let mut events = event::events_by_type<RecordingPublishedEvent<RecordingShare>>();
    assert_eq!(events.length(), 1);
    let (event_recording_id, event_recording_admin_cap_id, event_composition_id) =
        recording::recording_published_event_fields(&events.pop_back());
    assert_eq!(event_recording_id, recording_id);
    assert_eq!(event_recording_admin_cap_id, object::id(&cap));
    assert_eq!(event_composition_id, composition_id);
    cap
}

fun publish_release(scenario: &mut test_scenario::Scenario): (release::ReleaseAdminCap, ID) {
    let ctx = scenario.ctx();
    let recording_id = test_helpers::fake_id(ctx);
    let (release, cap) = release::new_for_testing(vector[recording_id], ctx);
    let release_id = object::id(&release);
    release.publish(&cap);
    let mut events = event::events_by_type<ReleasePublishedEvent>();
    assert!(!events.is_empty());
    let (event_release_id, event_release_admin_cap_id, event_recording_ids) =
        release::release_published_event_fields(&events.pop_back());
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_release_admin_cap_id, object::id(&cap));
    assert_eq!(event_recording_ids, vector[recording_id]);
    (cap, release_id)
}

// === Composition ===

#[test]
fun composition_uid_mut_works_after_publish() {
    let mut scenario = test_scenario::begin(OWNER);
    let cap = publish_composition(&mut scenario);
    scenario.next_tx(OWNER);
    let mut composition = scenario.take_shared<Composition<CompositionShare>>();
    dynamic_field::add(composition.uid_mut(&cap), b"extension", 42u64);
    assert!(dynamic_field::exists(composition.uid(), b"extension"));
    assert!(*dynamic_field::borrow<vector<u8>, u64>(composition.uid(), b"extension") == 42);
    test_scenario::return_shared(composition);
    destroy(cap);
    scenario.end();
}

// === Recording ===

#[test]
fun recording_uid_mut_works_after_publish() {
    let mut scenario = test_scenario::begin(OWNER);
    let cap = publish_recording(&mut scenario);
    scenario.next_tx(OWNER);
    let mut recording = scenario.take_shared<Recording<RecordingShare>>();
    dynamic_field::add(recording.uid_mut(&cap), b"master", 7u64);
    assert!(dynamic_field::exists(recording.uid(), b"master"));
    test_scenario::return_shared(recording);
    destroy(cap);
    scenario.end();
}

// === Release ===

#[test]
fun release_publish_twice_emits_again() {
    let mut scenario = test_scenario::begin(OWNER);
    let (cap, release_id) = publish_release(&mut scenario);
    scenario.next_tx(OWNER);
    let release = scenario.take_shared<Release>();
    release.publish(&cap);
    let mut events = event::events_by_type<ReleasePublishedEvent>();
    assert_eq!(events.length(), 1);
    let (event_release_id, _, _) = release::release_published_event_fields(&events.pop_back());
    assert_eq!(event_release_id, release_id);
    destroy(cap);
    scenario.end();
}

#[test]
fun release_uid_mut_works_after_publish() {
    let mut scenario = test_scenario::begin(OWNER);
    let (cap, _release_id) = publish_release(&mut scenario);
    scenario.next_tx(OWNER);
    let mut release = scenario.take_shared<Release>();
    dynamic_field::add(release.uid_mut(&cap), b"metadata", 9u64);
    assert!(dynamic_field::exists(release.uid(), b"metadata"));
    test_scenario::return_shared(release);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun release_publish_with_foreign_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (release, cap) = release::new_for_testing(vector[test_helpers::fake_id(ctx)], ctx);
    let (other_release, other_cap) = release::new_for_testing(
        vector[test_helpers::fake_id(ctx)],
        ctx,
    );
    release.publish(&other_cap);
    destroy(cap);
    destroy(other_release);
    abort
}

#[test]
fun published_release_keeps_track_order() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let recording_ids = vector::tabulate!(3, |_| test_helpers::fake_id(ctx));
    let (release, cap) = release::new_for_testing(recording_ids, ctx);
    release.publish(&cap);
    scenario.next_tx(STRANGER);
    let release = scenario.take_shared<Release>();
    assert_eq!(*release.recording_ids(), recording_ids);
    test_scenario::return_shared(release);
    destroy(cap);
    scenario.end();
}

#[test]
fun release_dynamic_field_attached_before_publish_survives() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let (mut release, cap) = release::new_for_testing(vector[test_helpers::fake_id(ctx)], ctx);
    dynamic_field::add(release.uid_mut(&cap), b"cover", 5u64);
    release.publish(&cap);
    scenario.next_tx(STRANGER);
    let release = scenario.take_shared<Release>();
    assert_eq!(*dynamic_field::borrow<vector<u8>, u64>(release.uid(), b"cover"), 5);
    test_scenario::return_shared(release);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun release_uid_mut_wrong_cap_aborts() {
    let mut scenario = test_scenario::begin(OWNER);
    let (owner_cap, owner_release_id) = publish_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let (stranger_cap, _stranger_release_id) = publish_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut owner_release = test_scenario::take_shared_by_id<Release>(&scenario, owner_release_id);
    let _uid = owner_release.uid_mut(&stranger_cap);
    test_scenario::return_shared(owner_release);
    destroy(owner_cap);
    destroy(stranger_cap);
    abort
}
