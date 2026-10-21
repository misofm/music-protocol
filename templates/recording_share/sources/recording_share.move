// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module recording_share::recording_share;

// === Imports ===

use sui::coin::TreasuryCap;
use sui::coin_registry::{Self, CoinRegistry};

// === Structs ===

public struct RecordingShare has key {
    id: UID,
}

public struct InitializeCurrencyTicket has key, store {
    id: UID,
}

// === Initializer ===

fun init(ctx: &mut TxContext) {
    transfer::transfer(InitializeCurrencyTicket { id: object::new(ctx) }, ctx.sender());
}

// === Public Functions ===

public fun initialize_currency(
    registry: &mut CoinRegistry,
    ticket: InitializeCurrencyTicket,
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
