// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::wrong_module;

use sui::coin::TreasuryCap;
use sui::coin_registry::{Self, Currency, CoinRegistry};

public struct CompositionShare has key { id: UID }

public fun canonical(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<CompositionShare>, TreasuryCap<CompositionShare>) {
    let (initializer, treasury_cap) = coin_registry::new_currency<CompositionShare>(
        registry,
        6,
        b"CSHARE".to_string(),
        b"Composition Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let (mut currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(
        initializer,
        ctx,
    );
    currency.delete_metadata_cap(metadata_cap);
    (currency, treasury_cap)
}
