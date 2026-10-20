#[test_only]
module musicos::composition_tests;

use std::unit_test::destroy;
use sui::test_scenario;
use musicos::composition::{Self, Composition};
use musicos::test_helpers::CompositionShare;

const OWNER: address = @0xA1;

// === Lifecycle ===

#[test]
fun test_new_composition() {
    let ctx = &mut tx_context::dummy();
    let (comp, cap) = composition::new_for_testing<CompositionShare>(ctx);
    destroy(comp);
    destroy(cap);
}

/// `publish` shares the composition: publish in one transaction, re-fetch it
/// via `take_shared` in the next.
#[test]
fun test_publish_composition() {
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
