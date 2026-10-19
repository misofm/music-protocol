// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// The share coin type for one recording. Publish an unchanged copy of this
/// package per work: publishing sends a one-time ticket to the publisher,
/// `initialize_currency` registers the currency with the canonical metadata, and
/// `musicos::recording::new` then consumes the treasury cap.
module recording_share::recording_share;

// === Imports ===

use sui::coin::TreasuryCap;
use sui::coin_registry::{Self, CoinRegistry};

// === Structs ===

/// The recording's share coin type. Never instantiated.
public struct RecordingShare has key {
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
/// treasury cap. Supply stays zero until `musicos::recording::new`.
public fun initialize_currency(
    ticket: InitializeCurrencyTicket,
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): TreasuryCap<RecordingShare> {
    let InitializeCurrencyTicket { id } = ticket;
    id.delete();
    let (initializer, treasury_cap) = coin_registry::new_currency<RecordingShare>(
        registry,
        6,
        b"RSHARE".to_string(),
        b"Recording Share".to_string(),
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
