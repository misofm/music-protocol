// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module composition_share::composition_share;

use sui::{coin::TreasuryCap, coin_registry::{Self, CoinRegistry}};

// === Structs ===

public struct CompositionShare has key {
    id: UID,
}

public struct InitializeCurrencyTicket has key, store {
    id: UID,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::transfer(InitializeCurrencyTicket { id: object::new(ctx) }, ctx.sender());
}

public fun initialize_currency(
    registry: &mut CoinRegistry,
    ticket: InitializeCurrencyTicket,
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
    init(ctx);
}
