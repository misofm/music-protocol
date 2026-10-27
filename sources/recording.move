// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module miso_music::recording;

use miso_music::composition::Composition;
use share::share;
use sui::{
    balance::Balance,
    coin::TreasuryCap,
    coin_registry::Currency,
    derived_object::{Self, claim},
    event::emit
};

// === Constants ===

const SHARE_MODULE: vector<u8> = b"recording_share";
const SHARE_DATATYPE: vector<u8> = b"RecordingShare";
const SHARE_DECIMALS: u8 = 6;
const SHARE_SYMBOL: vector<u8> = b"RSHARE";
const SHARE_NAME: vector<u8> = b"Recording Share";
const SHARE_SUPPLY: u64 = 100_000_000_000_000;

// === Structs ===

public struct Recording<phantom RecordingShare> has key {
    id: UID,
    composition_id: ID,
}

public struct RecordingAdminCap<phantom RecordingShare> has key, store {
    id: UID,
}

public struct RecordingRegistry has key {
    id: UID,
}

public struct RecordingKey<phantom RecordingShare>() has copy, drop, store;

public struct RecordingAdminCapKey() has copy, drop, store;

// === Events ===

public struct RecordingPublishedEvent<phantom RecordingShare> has copy, drop {
    recording_id: ID,
    recording_admin_cap_id: ID,
    composition_id: ID,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(RecordingRegistry { id: object::new(ctx) });
}

public fun new<RecordingShare: key, CompositionShare>(
    registry: &mut RecordingRegistry,
    currency: &mut Currency<RecordingShare>,
    composition: &Composition<CompositionShare>,
    treasury_cap: TreasuryCap<RecordingShare>,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>, Balance<RecordingShare>) {
    let shares = share::mint(
        currency,
        treasury_cap,
        SHARE_MODULE,
        SHARE_DATATYPE,
        SHARE_DECIMALS,
        SHARE_SYMBOL.to_string(),
        SHARE_NAME.to_string(),
        b"".to_string(),
        b"".to_string(),
        SHARE_SUPPLY,
    );
    let (recording, cap) = new_internal!<RecordingShare>(
        claim(&mut registry.id, RecordingKey<RecordingShare>()),
        object::id(composition),
    );
    (recording, cap, shares)
}

// === View Functions ===

public fun derive_address<RecordingShare>(registry: &RecordingRegistry): address {
    derived_object::derive_address(object::id(registry), RecordingKey<RecordingShare>())
}

public fun composition_id<RecordingShare>(self: &Recording<RecordingShare>): ID {
    self.composition_id
}

public fun uid<RecordingShare>(self: &Recording<RecordingShare>): &UID {
    &self.id
}

// === Admin Functions ===

public fun publish<RecordingShare>(
    self: Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    let recording_id = object::id(&self);
    let composition_id = self.composition_id;
    transfer::share_object(self);
    emit(RecordingPublishedEvent<RecordingShare> {
        recording_id,
        recording_admin_cap_id: object::id(cap),
        composition_id,
    });
}

public fun uid_mut<RecordingShare>(
    self: &mut Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
): &mut UID {
    &mut self.id
}

// === Private Functions ===

macro fun new_internal<$RecordingShare>(
    $id: UID,
    $composition_id: ID,
): (Recording<$RecordingShare>, RecordingAdminCap<$RecordingShare>) {
    let mut recording = Recording<$RecordingShare> {
        id: $id,
        composition_id: $composition_id,
    };
    let cap = RecordingAdminCap<$RecordingShare> {
        id: claim(&mut recording.id, RecordingAdminCapKey()),
    };
    (recording, cap)
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun new_for_testing<RecordingShare>(
    composition_id: ID,
    ctx: &mut TxContext,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>) {
    new_internal!<RecordingShare>(object::new(ctx), composition_id)
}

#[test_only]
public fun new_recording_registry_for_testing(ctx: &mut TxContext): RecordingRegistry {
    RecordingRegistry { id: object::new(ctx) }
}

#[test_only]
public fun share_supply_for_testing(): u64 { SHARE_SUPPLY }

#[test_only]
public fun recording_published_event_fields_for_testing<RecordingShare>(
    event: &RecordingPublishedEvent<RecordingShare>,
): (ID, ID, ID) {
    let RecordingPublishedEvent { recording_id, recording_admin_cap_id, composition_id } = event;
    (*recording_id, *recording_admin_cap_id, *composition_id)
}
