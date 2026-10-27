// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::composition_tests;

use miso_music::{composition::{Self, Composition}, test_helpers::CompositionShare};
use std::unit_test::destroy;
use sui::test_scenario;

const OWNER: address = @0xA1;

// === Lifecycle ===

#[test]
fun new_returns_composition_and_cap() {
    let ctx = &mut tx_context::dummy();
    let (composition, cap) = composition::new_for_testing<CompositionShare>(ctx);
    destroy(composition);
    destroy(cap);
}

#[test]
fun publish_shares_the_composition() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let (composition, cap) = composition::new_for_testing<CompositionShare>(ctx);
    composition.publish(&cap);
    scenario.next_tx(OWNER);
    let composition = scenario.take_shared<Composition<CompositionShare>>();
    test_scenario::return_shared(composition);
    destroy(cap);
    scenario.end();
}
