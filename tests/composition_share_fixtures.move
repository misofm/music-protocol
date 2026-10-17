/// Currencies with configurable metadata for `share::mint` check tests.
/// Each test builds its own registry, so the same type can be registered once
/// per test. `coin_registry::new_currency` must be called from the type's module.
#[test_only]
module musicos::composition_share;

use std::string::String;
use sui::coin::{TreasuryCap, DenyCapV2};
use sui::coin_registry::{Self, Currency, CoinRegistry};

/// Correct module and datatype names.
public struct CompositionShare has key { id: UID }
/// Correct module, wrong datatype name.
public struct WrongName has key { id: UID }

/// A registry for one test; the dummy context's sender is the system address.
public fun registry(ctx: &mut TxContext): CoinRegistry {
    coin_registry::create_coin_data_registry_for_testing(ctx)
}

/// Canonical composition share metadata with the metadata cap deleted.
public fun canonical(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<CompositionShare>, TreasuryCap<CompositionShare>) {
    custom(registry, 6, b"CSHARE".to_string(), b"Composition Share".to_string(), b"".to_string(), b"".to_string(), ctx)
}

/// Arbitrary metadata with the metadata cap deleted.
public fun custom(
    registry: &mut CoinRegistry,
    decimals: u8,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
    ctx: &mut TxContext,
): (Currency<CompositionShare>, TreasuryCap<CompositionShare>) {
    let (initializer, treasury_cap) = coin_registry::new_currency<CompositionShare>(
        registry, decimals, symbol, name, description, icon_url, ctx,
    );
    let (mut currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    currency.delete_metadata_cap(metadata_cap);
    (currency, treasury_cap)
}

/// Canonical metadata but the metadata cap is kept, so metadata stays mutable.
public fun unlocked(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<CompositionShare>, TreasuryCap<CompositionShare>, coin_registry::MetadataCap<CompositionShare>) {
    let (initializer, treasury_cap) = coin_registry::new_currency<CompositionShare>(
        registry, 6, b"CSHARE".to_string(), b"Composition Share".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    (currency, treasury_cap, metadata_cap)
}

/// Canonical metadata on a regulated currency.
public fun regulated(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<CompositionShare>, TreasuryCap<CompositionShare>, DenyCapV2<CompositionShare>) {
    let (mut initializer, treasury_cap) = coin_registry::new_currency<CompositionShare>(
        registry, 6, b"CSHARE".to_string(), b"Composition Share".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    let deny_cap = initializer.make_regulated(false, ctx);
    let (mut currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    currency.delete_metadata_cap(metadata_cap);
    (currency, treasury_cap, deny_cap)
}

/// Canonical metadata on the wrongly named `WrongName` type.
public fun wrong_name(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<WrongName>, TreasuryCap<WrongName>) {
    let (initializer, treasury_cap) = coin_registry::new_currency<WrongName>(
        registry, 6, b"CSHARE".to_string(), b"Composition Share".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    let (mut currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    currency.delete_metadata_cap(metadata_cap);
    (currency, treasury_cap)
}
