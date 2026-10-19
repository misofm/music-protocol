// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module musicos::track_tests;

use std::unit_test::assert_eq;
use musicos::test_helpers;
use musicos::track;

#[test]
fun consent_unwraps_to_release_and_recording() {
    let ctx = &mut tx_context::dummy();
    let recording_id = test_helpers::fake_id(ctx);
    let release_id = test_helpers::fake_id(ctx);
    let consent = track::consent_for_testing(recording_id, release_id);
    assert_eq!(consent.release_id(), release_id);
    assert_eq!(consent.recording_id(), recording_id);
    let (consented_release_id, consented_recording_id) = consent.into_parts();
    assert_eq!(consented_release_id, release_id);
    assert_eq!(consented_recording_id, recording_id);
}
