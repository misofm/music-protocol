// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::production_constructor_tests;

use composition_share::composition_share::{
    Self as composition_template,
    CompositionShare,
    InitializeCurrencyTicket as CompositionTicket,
};
use miso_music::{
    composition::{
        Self,
        Composition,
        CompositionAdminCap,
        CompositionPublishedEvent,
        CompositionRegistry,
    },
    composition_share as fixture,
    recording::{Self, Recording, RecordingAdminCap, RecordingPublishedEvent, RecordingRegistry},
    wrong_module
};
use recording_share::recording_share::{
    Self as recording_template,
    RecordingShare,
    InitializeCurrencyTicket as RecordingTicket,
};
use share::share;
use std::unit_test::{assert_eq, destroy};
use sui::{
    balance::Balance,
    coin::TreasuryCap,
    coin_registry::{Self, CoinRegistry, Currency},
    event,
    test_scenario
};

const SYSTEM: address = @0x0;
const SONGWRITER: address = @0xA1;
const ARTIST: address = @0xA2;

// === Template flow ===

#[test]
fun templates_create_composition_and_recording() {
    let mut scenario = test_scenario::begin(SYSTEM);
    coin_registry::create_coin_data_registry_for_testing(scenario.ctx()).share_for_testing();
    composition::init_for_testing(scenario.ctx());
    recording::init_for_testing(scenario.ctx());
    scenario.next_tx(SONGWRITER);
    composition_template::init_for_testing(scenario.ctx());
    scenario.next_tx(SONGWRITER);
    let ticket = scenario.take_from_sender<CompositionTicket>();
    let mut registry = scenario.take_shared<CoinRegistry>();
    let treasury_cap = composition_template::initialize_currency(
        &mut registry,
        ticket,
        scenario.ctx(),
    );
    test_scenario::return_shared(registry);
    scenario.next_tx(SONGWRITER);
    let mut currency = scenario.take_shared<Currency<CompositionShare>>();
    let mut composition_registry = scenario.take_shared<CompositionRegistry>();
    let (composition, composition_cap, shares) = composition::new(
        &mut composition_registry,
        &mut currency,
        treasury_cap,
    );
    let composition_id = object::id(&composition);
    assert_eq!(
        composition_id.to_address(),
        composition::derive_address<CompositionShare>(&composition_registry),
    );
    test_scenario::return_shared(composition_registry);
    assert_eq!(shares.value(), composition::share_supply_for_testing());
    assert!(currency.is_supply_fixed());
    assert_eq!(currency.total_supply(), option::some(composition::share_supply_for_testing()));
    composition.publish(&composition_cap);
    let mut events = event::events_by_type<CompositionPublishedEvent<CompositionShare>>();
    let (
        event_composition_id,
        event_composition_admin_cap_id,
    ) = composition::composition_published_event_fields_for_testing(&events.pop_back());
    assert_eq!(event_composition_id, composition_id);
    assert_eq!(event_composition_admin_cap_id, object::id(&composition_cap));
    test_scenario::return_shared(currency);
    transfer::public_transfer(composition_cap, SONGWRITER);
    destroy(shares);
    scenario.next_tx(ARTIST);
    recording_template::init_for_testing(scenario.ctx());
    scenario.next_tx(ARTIST);
    let ticket = scenario.take_from_sender<RecordingTicket>();
    let mut registry = scenario.take_shared<CoinRegistry>();
    let treasury_cap = recording_template::initialize_currency(
        &mut registry,
        ticket,
        scenario.ctx(),
    );
    test_scenario::return_shared(registry);
    scenario.next_tx(ARTIST);
    let composition = scenario.take_shared<Composition<CompositionShare>>();
    let mut currency = scenario.take_shared<Currency<RecordingShare>>();
    let mut recording_registry = scenario.take_shared<RecordingRegistry>();
    let (recording, recording_cap, shares) = recording::new(
        &mut recording_registry,
        &mut currency,
        &composition,
        treasury_cap,
    );
    let recording_id = object::id(&recording);
    assert_eq!(
        recording_id.to_address(),
        recording::derive_address<RecordingShare>(&recording_registry),
    );
    test_scenario::return_shared(recording_registry);
    assert_eq!(recording.composition_id(), composition_id);
    assert_eq!(shares.value(), recording::share_supply_for_testing());
    recording.publish(&recording_cap);
    let mut events = event::events_by_type<RecordingPublishedEvent<RecordingShare>>();
    let (
        event_recording_id,
        event_recording_admin_cap_id,
        event_composition_id,
    ) = recording::recording_published_event_fields_for_testing(&events.pop_back());
    assert_eq!(event_recording_id, recording_id);
    assert_eq!(event_recording_admin_cap_id, object::id(&recording_cap));
    assert_eq!(event_composition_id, composition_id);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(currency);
    transfer::public_transfer(recording_cap, ARTIST);
    destroy(shares);
    scenario.next_tx(ARTIST);
    let mut recording = scenario.take_shared<Recording<RecordingShare>>();
    let recording_cap = scenario.take_from_sender<RecordingAdminCap<RecordingShare>>();
    assert_eq!(recording.uid_mut(&recording_cap).to_inner(), recording_id);
    test_scenario::return_shared(recording);
    scenario.return_to_sender(recording_cap);
    scenario.next_tx(SONGWRITER);
    let mut composition = scenario.take_shared<Composition<CompositionShare>>();
    let composition_cap = scenario.take_from_sender<CompositionAdminCap<CompositionShare>>();
    assert_eq!(composition.uid_mut(&composition_cap).to_inner(), composition_id);
    test_scenario::return_shared(composition);
    scenario.return_to_sender(composition_cap);
    scenario.end();
}

// === share::mint checks ===

fun new_composition<CompositionShare: key>(
    mut currency: Currency<CompositionShare>,
    treasury_cap: TreasuryCap<CompositionShare>,
    registry: CoinRegistry,
    ctx: &mut TxContext,
) {
    let mut composition_registry = composition::new_composition_registry_for_testing(ctx);
    let (composition, cap, shares): (
        Composition<CompositionShare>,
        CompositionAdminCap<CompositionShare>,
        Balance<CompositionShare>,
    ) = composition::new(&mut composition_registry, &mut currency, treasury_cap);
    destroy(composition);
    destroy(cap);
    destroy(shares);
    destroy(currency);
    destroy(registry);
    destroy(composition_registry);
}

#[test]
fun canonical_currency_is_accepted() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::canonical(&mut registry, ctx);
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_datatype_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::wrong_name(&mut registry, ctx);
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_module_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = wrong_module::canonical(&mut registry, ctx);
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun composition_type_rejected_for_recording() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::canonical(&mut registry, ctx);
    let (composition, composition_cap) = composition::new_for_testing<fixture::CompositionShare>(
        ctx,
    );
    let mut recording_registry = recording::new_recording_registry_for_testing(ctx);
    let (recording, recording_cap, shares) = recording::new(
        &mut recording_registry,
        &mut currency,
        &composition,
        treasury_cap,
    );
    destroy(composition);
    destroy(composition_cap);
    destroy(recording);
    destroy(recording_cap);
    destroy(shares);
    destroy(currency);
    destroy(registry);
    destroy(recording_registry);
}

#[test, expected_failure(abort_code = share::EInvalidDecimals)]
fun wrong_decimals_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry,
        9,
        b"CSHARE".to_string(),
        b"Composition Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidName)]
fun wrong_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry,
        6,
        b"CSHARE".to_string(),
        b"Miso Music Composition Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidSymbol)]
fun wrong_symbol_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry,
        6,
        b"RSHARE".to_string(),
        b"Composition Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidDescription)]
fun nonempty_description_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry,
        6,
        b"CSHARE".to_string(),
        b"Composition Share".to_string(),
        b"A song".to_string(),
        b"".to_string(),
        ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidIconUrl)]
fun nonempty_icon_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry,
        6,
        b"CSHARE".to_string(),
        b"Composition Share".to_string(),
        b"".to_string(),
        b"https://example.com/icon.png".to_string(),
        ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}
