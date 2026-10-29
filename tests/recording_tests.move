// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::recording_tests;

use miso_music::{recording::{Self, Recording}, test_helpers::{Self, RecordingShare}};
use std::unit_test::destroy;
use sui::test_scenario;

const OWNER: address = @0xA1;

// === Lifecycle ===

#[test]
fun new_returns_recording_and_cap() {
    let ctx = &mut tx_context::dummy();
    let (recording, cap) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    destroy(recording);
    destroy(cap);
}

#[test]
fun shares_the_recording() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let (recording, cap) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    recording.share();
    scenario.next_tx(OWNER);
    let recording = scenario.take_shared<Recording<RecordingShare>>();
    test_scenario::return_shared(recording);
    destroy(cap);
    scenario.end();
}
