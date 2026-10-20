// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Production constructors: the full publish flow through the share-coin
/// templates, and every `share::mint` check as configured by core.
#[test_only]
module musicos::production_constructor_tests;

use std::unit_test::{assert_eq, destroy};
use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::{Self, CoinRegistry, Currency};
use sui::event;
use sui::test_scenario;
use share::share;
use composition_share::composition_share::{
    Self as composition_template,
    CompositionShare,
    InitializeCurrencyTicket as CompositionTicket,
};
use recording_share::recording_share::{
    Self as recording_template,
    RecordingShare,
    InitializeCurrencyTicket as RecordingTicket,
};
use musicos::composition::{
    Self,
    Composition,
    CompositionAdminCap,
    CompositionPublishedEvent,
    CompositionRegistry,
};
use musicos::composition_share as fixture;
use musicos::recording::{
    Self,
    Recording,
    RecordingAdminCap,
    RecordingPublishedEvent,
    RecordingRegistry,
};
use musicos::wrong_module;

const SYSTEM: address = @0x0;
const SONGWRITER: address = @0xA1;
const ARTIST: address = @0xA2;

// === Template flow ===

/// Publish (init ticket), `initialize_currency`, then `new` + `publish` in a
/// later transaction, for a composition and a recording of it.
#[test]
fun templates_create_composition_and_recording() {
    let mut scenario = test_scenario::begin(SYSTEM);
    coin_registry::create_coin_data_registry_for_testing(scenario.ctx()).share_for_testing();
    composition::init_for_testing(scenario.ctx());
    recording::init_for_testing(scenario.ctx());

    // Tx 1 (SONGWRITER): publish the template, then initialize the currency.
    scenario.next_tx(SONGWRITER);
    composition_template::init_for_testing(scenario.ctx());
    scenario.next_tx(SONGWRITER);
    let ticket = scenario.take_from_sender<CompositionTicket>();
    let mut registry = scenario.take_shared<CoinRegistry>();
    let treasury_cap = ticket.initialize_currency(&mut registry, scenario.ctx());
    test_scenario::return_shared(registry);

    // Tx 2 (SONGWRITER): create and publish the composition.
    scenario.next_tx(SONGWRITER);
    let mut currency = scenario.take_shared<Currency<CompositionShare>>();
    let mut composition_registry = scenario.take_shared<CompositionRegistry>();
    let (comp, comp_cap, shares) = composition::new(
        &mut composition_registry,
        &mut currency,
        treasury_cap,
    );
    let composition_id = object::id(&comp);
    assert_eq!(
        composition_id.to_address(),
        composition::derive_address<CompositionShare>(&composition_registry),
    );
    test_scenario::return_shared(composition_registry);
    assert_eq!(shares.value(), composition::share_supply());
    assert!(currency.is_supply_fixed());
    assert_eq!(currency.total_supply(), option::some(composition::share_supply()));
    comp.publish(&comp_cap);
    let mut events = event::events_by_type<CompositionPublishedEvent<CompositionShare>>();
    assert_eq!(composition::composition_published_event_fields(events.pop_back()), composition_id);
    test_scenario::return_shared(currency);
    transfer::public_transfer(comp_cap, SONGWRITER);
    destroy(shares);

    // Tx 3-4 (ARTIST): recording template, then the recording.
    scenario.next_tx(ARTIST);
    recording_template::init_for_testing(scenario.ctx());
    scenario.next_tx(ARTIST);
    let ticket = scenario.take_from_sender<RecordingTicket>();
    let mut registry = scenario.take_shared<CoinRegistry>();
    let treasury_cap = ticket.initialize_currency(&mut registry, scenario.ctx());
    test_scenario::return_shared(registry);

    scenario.next_tx(ARTIST);
    let comp = scenario.take_shared<Composition<CompositionShare>>();
    let mut currency = scenario.take_shared<Currency<RecordingShare>>();
    let mut recording_registry = scenario.take_shared<RecordingRegistry>();
    let (rec, rec_cap, shares) = recording::new(
        &mut recording_registry,
        &comp,
        &mut currency,
        treasury_cap,
    );
    let recording_id = object::id(&rec);
    assert_eq!(
        recording_id.to_address(),
        recording::derive_address<RecordingShare>(&recording_registry),
    );
    test_scenario::return_shared(recording_registry);
    assert_eq!(rec.composition_id(), composition_id);
    assert_eq!(shares.value(), composition::share_supply());
    rec.publish(&rec_cap);
    let mut events = event::events_by_type<RecordingPublishedEvent<RecordingShare>>();
    let (event_recording, event_composition) =
        recording::recording_published_event_fields(events.pop_back());
    assert_eq!(event_recording, recording_id);
    assert_eq!(event_composition, composition_id);
    test_scenario::return_shared(comp);
    test_scenario::return_shared(currency);
    transfer::public_transfer(rec_cap, ARTIST);
    destroy(shares);

    // Later: the caps still open their works' UIDs.
    scenario.next_tx(ARTIST);
    let mut rec = scenario.take_shared<Recording<RecordingShare>>();
    let rec_cap = scenario.take_from_sender<RecordingAdminCap<RecordingShare>>();
    assert_eq!(rec.uid_mut(&rec_cap).to_inner(), recording_id);
    test_scenario::return_shared(rec);
    scenario.return_to_sender(rec_cap);

    scenario.next_tx(SONGWRITER);
    let mut comp = scenario.take_shared<Composition<CompositionShare>>();
    let comp_cap = scenario.take_from_sender<CompositionAdminCap<CompositionShare>>();
    assert_eq!(comp.uid_mut(&comp_cap).to_inner(), composition_id);
    test_scenario::return_shared(comp);
    scenario.return_to_sender(comp_cap);
    scenario.end();
}

// === share::mint checks ===

/// Runs `composition::new` on a fixture currency and cleans up on success.
fun new_composition<Share: key>(
    mut currency: Currency<Share>,
    treasury_cap: TreasuryCap<Share>,
    registry: CoinRegistry,
    ctx: &mut TxContext,
) {
    let mut composition_registry = composition::new_registry_for_testing(ctx);
    let (comp, cap, shares): (Composition<Share>, CompositionAdminCap<Share>, Balance<Share>) =
        composition::new(&mut composition_registry, &mut currency, treasury_cap);
    destroy(comp);
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

/// A composition share currency can't back a recording.
#[test, expected_failure(abort_code = share::EInvalidType)]
fun composition_type_rejected_for_recording() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::canonical(&mut registry, ctx);
    let (comp, comp_cap) = composition::new_for_testing<fixture::CompositionShare>(ctx);
    let mut recording_registry = recording::new_registry_for_testing(ctx);
    let (rec, rec_cap, shares) = recording::new(
        &mut recording_registry,
        &comp,
        &mut currency,
        treasury_cap,
    );
    destroy(comp);
    destroy(comp_cap);
    destroy(rec);
    destroy(rec_cap);
    destroy(shares);
    destroy(currency);
    destroy(registry);
    destroy(recording_registry);
}

#[test, expected_failure(abort_code = share::ETreasuryMismatch)]
fun foreign_treasury_cap_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let mut other_registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::canonical(&mut registry, ctx);
    let (other_currency, other_treasury_cap) = fixture::canonical(&mut other_registry, ctx);
    destroy(other_currency);
    destroy(other_registry);
    destroy(treasury_cap);
    new_composition(currency, other_treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::ENotZeroSupply)]
fun minted_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, mut treasury_cap) = fixture::canonical(&mut registry, ctx);
    destroy(treasury_cap.mint_balance(1));
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::ERegulatedCurrency)]
fun regulated_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap, deny_cap) = fixture::regulated(&mut registry, ctx);
    destroy(deny_cap);
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EMetadataNotLocked)]
fun unlocked_metadata_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap, metadata_cap) = fixture::unlocked(&mut registry, ctx);
    destroy(metadata_cap);
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidDecimals)]
fun wrong_decimals_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry, 9, b"CSHARE".to_string(), b"Composition Share".to_string(),
        b"".to_string(), b"".to_string(), ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidName)]
fun wrong_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry, 6, b"CSHARE".to_string(), b"MusicOS Composition Share".to_string(),
        b"".to_string(), b"".to_string(), ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidSymbol)]
fun wrong_symbol_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry, 6, b"RSHARE".to_string(), b"Composition Share".to_string(),
        b"".to_string(), b"".to_string(), ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidDescription)]
fun nonempty_description_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry, 6, b"CSHARE".to_string(), b"Composition Share".to_string(),
        b"A song".to_string(), b"".to_string(), ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}

#[test, expected_failure(abort_code = share::EInvalidIconUrl)]
fun nonempty_icon_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::custom(
        &mut registry, 6, b"CSHARE".to_string(), b"Composition Share".to_string(),
        b"".to_string(), b"https://example.com/icon.png".to_string(), ctx,
    );
    new_composition(currency, treasury_cap, registry, ctx);
}
