// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::composition_tests;

use std::unit_test::destroy;
use sui::test_scenario;
use miso_music::composition::{Self, Composition};
use miso_music::test_helpers::CompositionShare;

const OWNER: address = @0xA1;

// === Lifecycle ===

#[test]
fun new_composition() {
    let ctx = &mut tx_context::dummy();
    let (comp, cap) = composition::new_for_testing<CompositionShare>(ctx);
    destroy(comp);
    destroy(cap);
}

#[test]
fun publish_composition() {
    let mut scenario = test_scenario::begin(OWNER);
    let ctx = scenario.ctx();
    let (comp, cap) = composition::new_for_testing<CompositionShare>(ctx);
    comp.publish(&cap); // shares the composition

    scenario.next_tx(OWNER);
    let comp = scenario.take_shared<Composition<CompositionShare>>();
    test_scenario::return_shared(comp);

    destroy(cap);
    scenario.end();
}
