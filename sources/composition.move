// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A musical composition and its canonical share coin `CompositionShare`.
/// Creation consumes the coin's treasury cap, so each share type backs exactly
/// one composition, and the 100M fixed supply goes to the creator. Embedded
/// state freezes at publication; extensions attach through admin-authorized
/// UID access. Objects are key-only: creation must end with publication in
/// the same transaction.
module musicos::composition;

// === Imports ===

use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::Currency;
use sui::derived_object::claim;
use sui::event::emit;

#[test_only]
use sui::bcs::to_bytes;

use share::share;

// === Errors ===

// State errors (10-19)
/// Operation requires Initialized state but composition is in a different state.
const ENotInitializedState: u64 = 10;

// === Constants ===

const SHARE_MODULE: vector<u8> = b"composition_share";
const SHARE_DATATYPE: vector<u8> = b"CompositionShare";
const SHARE_DECIMALS: u8 = 6;
const SHARE_NAME: vector<u8> = b"Composition Share";
const SHARE_SYMBOL: vector<u8> = b"CSHARE";
/// 100 million shares in base units.
const SHARE_SUPPLY: u64 = 100_000_000_000_000;

// === Structs ===

/// The underlying written work.
public struct Composition<phantom CompositionShare> has key {
    id: UID,
    /// Current lifecycle state.
    state: CompositionState,
}

/// Authorizes admin operations on the one composition of its share type.
/// Its address is derived from the composition under `CompositionAdminCapKey`.
public struct CompositionAdminCap<phantom CompositionShare> has key, store {
    id: UID,
}

/// Derivation key for `CompositionAdminCap`.
public struct CompositionAdminCapKey() has copy, drop, store;

// === Enums ===

/// Lifecycle state of a composition.
public enum CompositionState has drop, store {
    /// Created but not yet published.
    Initialized,
    /// Published and immutable.
    Published,
}

// === Events ===

/// Emitted once when the composition is published.
public struct CompositionPublishedEvent<phantom CompositionShare> has copy, drop {
    composition_id: ID,
}

// === Public Functions ===

/// Creates the composition and its admin cap from a fresh
/// `<package>::composition_share::CompositionShare` currency, returning the
/// full share supply. See `share::mint` for the currency checks.
public fun new<CompositionShare>(
    currency: &mut Currency<CompositionShare>,
    treasury_cap: TreasuryCap<CompositionShare>,
    ctx: &mut TxContext,
): (Composition<CompositionShare>, CompositionAdminCap<CompositionShare>, Balance<CompositionShare>) {
    let shares = share::mint(
        currency,
        treasury_cap,
        SHARE_MODULE,
        SHARE_DATATYPE,
        SHARE_DECIMALS,
        SHARE_NAME.to_string(),
        SHARE_SYMBOL.to_string(),
        b"".to_string(),
        b"".to_string(),
        SHARE_SUPPLY,
    );
    let (composition, cap) = new_internal(ctx);
    (composition, cap, shares)
}

/// Publishes the composition: shares it and freezes its embedded fields.
/// Aborts with `ENotInitializedState` unless `Initialized`.
public fun publish<CompositionShare>(
    mut self: Composition<CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
) {
    match (&self.state) {
        CompositionState::Initialized => {
            self.state = CompositionState::Published;
            let composition_id = object::id(&self);
            transfer::share_object(self);
            emit(CompositionPublishedEvent<CompositionShare> { composition_id });
        },
        _ => abort ENotInitializedState,
    }
}

// === View Functions ===

/// Read access to the composition's UID (dynamic fields).
public fun uid<CompositionShare>(self: &Composition<CompositionShare>): &UID {
    &self.id
}

// === Admin Functions ===

/// Mutable access to the composition's UID, gated by the admin cap. Works in
/// any lifecycle state: dynamic fields are the extension surface and stay
/// mutable after publish. A field keyed by a type private to another module
/// can only be added or removed through that module.
public fun uid_mut<CompositionShare>(
    self: &mut Composition<CompositionShare>,
    _: &CompositionAdminCap<CompositionShare>,
): &mut UID {
    &mut self.id
}

// === Private Functions ===

fun new_internal<CompositionShare>(
    ctx: &mut TxContext,
): (Composition<CompositionShare>, CompositionAdminCap<CompositionShare>) {
    let mut composition = Composition<CompositionShare> {
        id: object::new(ctx),
        state: CompositionState::Initialized,
    };
    let cap = CompositionAdminCap<CompositionShare> {
        id: claim(&mut composition.id, CompositionAdminCapKey()),
    };
    (composition, cap)
}

// === Test Functions ===

// State predicates are test-only: create-and-publish is atomic, so every
// composition a runtime caller can hold is `Published`.

#[test_only]
public fun is_initialized_state<CompositionShare>(self: &Composition<CompositionShare>): bool {
    match (&self.state) { CompositionState::Initialized => true, _ => false }
}

#[test_only]
public fun is_published_state<CompositionShare>(self: &Composition<CompositionShare>): bool {
    match (&self.state) { CompositionState::Published => true, _ => false }
}

#[test_only]
public fun share_supply(): u64 { SHARE_SUPPLY }

#[test_only]
public fun published_state_bcs_bytes(): vector<u8> {
    to_bytes(&CompositionState::Published)
}

/// Creates a composition without a currency, for tests that don't exercise shares.
#[test_only]
public fun new_for_testing<CompositionShare>(
    ctx: &mut TxContext,
): (Composition<CompositionShare>, CompositionAdminCap<CompositionShare>) {
    new_internal(ctx)
}

/// Unpacks a `CompositionPublishedEvent` (fields are module-private) for test assertions.
#[test_only]
public fun composition_published_event_fields<CompositionShare>(
    event: CompositionPublishedEvent<CompositionShare>,
): ID {
    let CompositionPublishedEvent { composition_id } = event;
    composition_id
}
