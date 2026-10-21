// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A musical composition and its canonical share coin `CompositionShare`.
/// Each composition is derived from the `CompositionRegistry` under its share
/// type, so its address follows from the type alone, and creation consumes
/// the coin's treasury cap, so each share type backs exactly one composition.
/// The 100M fixed supply goes to the creator. Extensions attach through
/// admin-authorized UID access.
/// Objects are key-only: creation must end with publication in the same
/// transaction.
module miso_music::composition;

// === Imports ===

use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::Currency;
use sui::derived_object::{Self, claim};
use sui::event::emit;
use share::share;

// === Constants ===

const SHARE_MODULE: vector<u8> = b"composition_share";
const SHARE_DATATYPE: vector<u8> = b"CompositionShare";
const SHARE_DECIMALS: u8 = 6;
const SHARE_SYMBOL: vector<u8> = b"CSHARE";
const SHARE_NAME: vector<u8> = b"Composition Share";
/// 100 million shares in base units.
const SHARE_SUPPLY: u64 = 100_000_000_000_000;

// === Structs ===

/// The underlying written work.
public struct Composition<phantom CompositionShare> has key {
    id: UID,
}

/// Authorizes admin operations on the one composition of its share type.
/// Its address is derived from the composition under `CompositionAdminCapKey`.
public struct CompositionAdminCap<phantom CompositionShare> has key, store {
    id: UID,
}

/// The derivation parent of every composition, created once at package
/// initialization with no other constructor or mutable UID accessor.
public struct CompositionRegistry has key {
    id: UID,
}

/// Derivation key for the composition of a share type.
public struct CompositionKey<phantom CompositionShare>() has copy, drop, store;

/// Derivation key for `CompositionAdminCap`.
public struct CompositionAdminCapKey() has copy, drop, store;

// === Events ===

/// Emitted once when the composition is published.
public struct CompositionPublishedEvent<phantom CompositionShare> has copy, drop {
    composition_id: ID,
    admin_cap_id: ID,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(CompositionRegistry { id: object::new(ctx) });
}

/// Creates the composition and its admin cap from a fresh
/// `<package>::composition_share::CompositionShare` currency, returning the
/// full share supply. See `share::mint` for the checks.
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
    (composition, cap, shares)
}

/// Publishes the composition by sharing it.
public fun publish<CompositionShare>(
    self: Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
) {
    let composition_id = object::id(&self);
    transfer::share_object(self);
    emit(CompositionPublishedEvent<CompositionShare> {
        composition_id,
        admin_cap_id: object::id(cap),
    });
}

// === View Functions ===

/// The address of the composition of `CompositionShare`. Not proof that it
/// exists.
public fun derive_address<CompositionShare>(registry: &CompositionRegistry): address {
    derived_object::derive_address(object::id(registry), CompositionKey<CompositionShare>())
}

/// Read access to the composition's UID (dynamic fields).
public fun uid<CompositionShare>(self: &Composition<CompositionShare>): &UID {
    &self.id
}

// === Admin Functions ===

/// Mutable access to the composition's UID, gated by the admin cap. Dynamic
/// fields are the extension surface and stay mutable after publish. A field
/// keyed by a type private to another module can only be added or removed
/// through that module.
public fun uid_mut<CompositionShare>(
    self: &mut Composition<CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
): &mut UID {
    &mut self.id
}

// === Private Functions ===

/// `$id` must be a direct `object::new` or `claim` call: object UIDs can't
/// be passed through a function.
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
public fun share_supply(): u64 { SHARE_SUPPLY }

/// Creates a composition without a currency, for tests that don't exercise
/// shares.
#[test_only]
public fun new_for_testing<CompositionShare>(
    ctx: &mut TxContext,
): (Composition<CompositionShare>, CompositionAdminCap<CompositionShare>) {
    new_internal!<CompositionShare>(object::new(ctx))
}

/// Runs the real module initializer, creating and sharing the registry.
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

/// Creates an unshared registry for tests.
#[test_only]
public fun new_registry_for_testing(ctx: &mut TxContext): CompositionRegistry {
    CompositionRegistry { id: object::new(ctx) }
}

/// Unpacks a `CompositionPublishedEvent` (fields are module-private) for test
/// assertions.
#[test_only]
public fun composition_published_event_fields<CompositionShare>(
    event: CompositionPublishedEvent<CompositionShare>,
): (ID, ID) {
    let CompositionPublishedEvent { composition_id, admin_cap_id } = event;
    (composition_id, admin_cap_id)
}
