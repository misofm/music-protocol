// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// The share coin type for one composition. Publish an unchanged copy of this
/// package per work: publishing sends a one-time ticket to the publisher,
/// `initialize_currency` registers the currency with the canonical metadata, and
/// `musicos::composition::new` then consumes the treasury cap.
module composition_share::composition_share;

// === Imports ===

use sui::coin::TreasuryCap;
use sui::coin_registry::{Self, CoinRegistry};

// === Structs ===

/// The composition's share coin type. Never instantiated.
public struct CompositionShare has key {
    id: UID,
}

/// Authorizes the single `initialize_currency` call.
public struct InitializeCurrencyTicket has key {
    id: UID,
}

// === Initializer ===

fun init(ctx: &mut TxContext) {
    transfer::transfer(InitializeCurrencyTicket { id: object::new(ctx) }, ctx.sender());
}

// === Public Functions ===

/// Registers the currency with locked canonical metadata and returns its
/// treasury cap. Supply stays zero until `musicos::composition::new`.
public fun initialize_currency(
    ticket: InitializeCurrencyTicket,
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): TreasuryCap<CompositionShare> {
    let InitializeCurrencyTicket { id } = ticket;
    id.delete();
    let (initializer, treasury_cap) = coin_registry::new_currency<CompositionShare>(
        registry,
        6,
        b"CSHARE".to_string(),
        b"Composition Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    initializer.finalize_and_delete_metadata_cap(ctx);
    treasury_cap
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}
