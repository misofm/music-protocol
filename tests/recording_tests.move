// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::recording_tests;

use std::unit_test::destroy;
use sui::test_scenario;
use miso_music::recording::{Self, Recording};
use miso_music::test_helpers::{Self, RecordingShare};

const OWNER: address = @0xA1;

/// `publish` shares the recording: publish in one transaction, re-fetch it
/// via `take_shared` in the next.
#[test]
fun publish_recording() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let (rec, cap) = recording::new_for_testing<RecordingShare>(
        test_helpers::fake_id(ctx),
        ctx,
    );
    rec.publish(&cap); // shares the recording

    scenario.next_tx(OWNER);
    let rec = scenario.take_shared<Recording<RecordingShare>>();
    test_scenario::return_shared(rec);

    destroy(cap);
    scenario.end();
}

// Id independence of recordings under one composition is covered by
// `production_constructor_tests`.
