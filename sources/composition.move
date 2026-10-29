// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module miso_music::composition;

use share::share;
use sui::{
    balance::Balance,
    coin::TreasuryCap,
    coin_registry::Currency,
    derived_object::{Self, claim},
    event::emit
};

// === Constants ===

const SHARE_MODULE: vector<u8> = b"composition_share";
const SHARE_DATATYPE: vector<u8> = b"CompositionShare";
const SHARE_DECIMALS: u8 = 6;
const SHARE_SYMBOL: vector<u8> = b"CSHARE";
const SHARE_NAME: vector<u8> = b"Composition Share";
const SHARE_SUPPLY: u64 = 100_000_000_000_000;

// === Structs ===

public struct Composition<phantom CompositionShare> has key {
    id: UID,
}

public struct CompositionAdminCap<phantom CompositionShare> has key, store {
    id: UID,
}

public struct CompositionRegistry has key {
    id: UID,
}

public struct CompositionKey<phantom CompositionShare>() has copy, drop, store;

public struct CompositionAdminCapKey() has copy, drop, store;

// === Events ===

public struct CompositionCreatedEvent<phantom CompositionShare> has copy, drop {
    composition_id: ID,
    composition_admin_cap_id: ID,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(CompositionRegistry { id: object::new(ctx) });
}

public fun new<CompositionShare: key>(
    registry: &mut CompositionRegistry,
    currency: &mut Currency<CompositionShare>,
    treasury_cap: TreasuryCap<CompositionShare>,
): (
    Composition<CompositionShare>,
    CompositionAdminCap<CompositionShare>,
    Balance<CompositionShare>,
) {
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
    let (composition, cap) = new_internal!<CompositionShare>(
        claim(&mut registry.id, CompositionKey<CompositionShare>()),
    );
    emit(CompositionCreatedEvent<CompositionShare> {
        composition_id: object::id(&composition),
        composition_admin_cap_id: object::id(&cap),
    });
    (composition, cap, shares)
}

// === View Functions ===

public fun derive_address<CompositionShare>(registry: &CompositionRegistry): address {
    derived_object::derive_address(object::id(registry), CompositionKey<CompositionShare>())
}

public fun uid<CompositionShare>(self: &Composition<CompositionShare>): &UID {
    &self.id
}

// === Admin Functions ===

public fun share<CompositionShare>(self: Composition<CompositionShare>) {
    transfer::share_object(self);
}

public fun uid_mut<CompositionShare>(
    self: &mut Composition<CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
): &mut UID {
    &mut self.id
}

// === Private Functions ===

macro fun new_internal<$CompositionShare>(
    $id: UID,
): (Composition<$CompositionShare>, CompositionAdminCap<$CompositionShare>) {
    let mut composition = Composition<$CompositionShare> { id: $id };
    let cap = CompositionAdminCap<$CompositionShare> {
        id: claim(&mut composition.id, CompositionAdminCapKey()),
    };
    (composition, cap)
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun new_for_testing<CompositionShare>(
    ctx: &mut TxContext,
): (Composition<CompositionShare>, CompositionAdminCap<CompositionShare>) {
    new_internal!<CompositionShare>(object::new(ctx))
}

#[test_only]
public fun new_composition_registry_for_testing(ctx: &mut TxContext): CompositionRegistry {
    CompositionRegistry { id: object::new(ctx) }
}

#[test_only]
public fun share_supply_for_testing(): u64 { SHARE_SUPPLY }

#[test_only]
public fun composition_created_fields_for_testing<CompositionShare>(
    event: &CompositionCreatedEvent<CompositionShare>,
): (ID, ID) {
    let CompositionCreatedEvent { composition_id, composition_admin_cap_id } = event;
    (*composition_id, *composition_admin_cap_id)
}
