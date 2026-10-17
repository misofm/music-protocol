// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Validates a work's share currency and mints its fixed supply.
/// Every work's share coin is identical apart from its package address.
module musicos::share_currency;

// === Imports ===

use std::ascii;
use std::string::String;
use std::type_name;

use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::Currency;

// === Errors ===

const EInvalidShareType: u64 = 0;
const ETreasuryMismatch: u64 = 1;
const ENotZeroSupply: u64 = 2;
const ERegulatedCurrency: u64 = 3;
const EMetadataNotLocked: u64 = 4;
const EInvalidDecimals: u64 = 5;
const EInvalidName: u64 = 6;
const EInvalidSymbol: u64 = 7;
const EInvalidDescription: u64 = 8;
const EInvalidIconUrl: u64 = 9;

// === Constants ===

/// 100 million shares in base units.
const SUPPLY: u64 = 100_000_000_000_000;
const DECIMALS: u8 = 6;

// === Package Functions ===

/// Checks the currency against the canonical share metadata, mints the full
/// supply and fixes it by consuming the treasury cap. Consuming the cap means
/// a currency can back only one work.
public(package) fun mint<T>(
    currency: &mut Currency<T>,
    mut treasury_cap: TreasuryCap<T>,
    module_name: vector<u8>,
    datatype_name: vector<u8>,
    name: String,
    symbol: String,
): Balance<T> {
    assert!(is_share_type<T>(module_name, datatype_name), EInvalidShareType);
    assert!(currency.treasury_cap_id() == option::some(object::id(&treasury_cap)), ETreasuryMismatch);
    assert!(treasury_cap.total_supply() == 0, ENotZeroSupply);
    assert!(!currency.is_regulated(), ERegulatedCurrency);
    assert!(currency.is_metadata_cap_deleted(), EMetadataNotLocked);
    assert!(currency.decimals() == DECIMALS, EInvalidDecimals);
    assert!(currency.name() == name, EInvalidName);
    assert!(currency.symbol() == symbol, EInvalidSymbol);
    assert!(currency.description().is_empty(), EInvalidDescription);
    assert!(currency.icon_url().is_empty(), EInvalidIconUrl);

    let shares = treasury_cap.mint_balance(SUPPLY);
    currency.make_supply_fixed(treasury_cap);
    shares
}

// === Private Functions ===

/// True only for exactly `<address>::<module_name>::<datatype_name>` with no
/// type arguments. Such a `key` struct can't be a one-time witness, so the
/// currency was created through `coin_registry`, not a legacy constructor.
fun is_share_type<T>(module_name: vector<u8>, datatype_name: vector<u8>): bool {
    let type_name = type_name::with_defining_ids<T>();
    if (type_name.is_primitive()) return false;
    let mut expected = type_name.address_string().into_bytes();
    expected.append(b"::");
    expected.append(module_name);
    expected.append(b"::");
    expected.append(datatype_name);
    type_name.as_string() == &ascii::string(expected)
}

// === Test Functions ===

#[test_only]
public fun supply(): u64 { SUPPLY }
