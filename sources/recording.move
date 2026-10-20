// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A recording of a composition and its canonical share coin `RecordingShare`.
/// Each recording is derived from the `RecordingRegistry` under its share
/// type, and creation consumes the coin's treasury cap, so each share type
/// backs exactly one recording. The 100M fixed supply goes to the creator.
/// The composition is only read, so recordings of one composition never
/// contend on it; its ID freezes at creation. Extensions attach through
/// admin-authorized UID access. Objects are key-only: creation must end with
/// publication in the same transaction.
module musicos::recording;

// === Imports ===

use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::Currency;
use sui::derived_object::{Self, claim};
use sui::event::emit;
use share::share;
use musicos::composition::Composition;

// === Constants ===

const SHARE_MODULE: vector<u8> = b"recording_share";
const SHARE_DATATYPE: vector<u8> = b"RecordingShare";
const SHARE_DECIMALS: u8 = 6;
const SHARE_NAME: vector<u8> = b"Recording Share";
const SHARE_SYMBOL: vector<u8> = b"RSHARE";
/// 100 million shares in base units.
const SHARE_SUPPLY: u64 = 100_000_000_000_000;

// === Structs ===

/// An audio recording of a composition.
public struct Recording<phantom RecordingShare> has key {
    id: UID,
    /// The parent composition identity.
    composition_id: ID,
}

/// Authorizes admin operations on the one recording of its share type.
/// Its address is derived from the recording under `RecordingAdminCapKey`.
public struct RecordingAdminCap<phantom RecordingShare> has key, store {
    id: UID,
}

/// The derivation parent of every recording, created once at package
/// initialization with no other constructor or mutable UID accessor.
public struct RecordingRegistry has key {
    id: UID,
}

/// Derivation key for the recording of a share type.
public struct RecordingKey<phantom RecordingShare>() has copy, drop, store;

/// Derivation key for `RecordingAdminCap`.
public struct RecordingAdminCapKey() has copy, drop, store;

// === Events ===

/// Emitted once when the recording is published.
public struct RecordingPublishedEvent<phantom RecordingShare> has copy, drop {
    recording_id: ID,
    composition_id: ID,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(RecordingRegistry { id: object::new(ctx) });
}

/// Creates a recording of `composition` and its admin cap from a fresh
/// `<package>::recording_share::RecordingShare` currency, returning the full
/// share supply. See `share::mint` for the checks.
public fun new<RecordingShare: key, CompositionShare>(
    registry: &mut RecordingRegistry,
    composition: &Composition<CompositionShare>,
    currency: &mut Currency<RecordingShare>,
    treasury_cap: TreasuryCap<RecordingShare>,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>, Balance<RecordingShare>) {
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
    let (recording, cap) = new_internal!<RecordingShare>(
        claim(&mut registry.id, RecordingKey<RecordingShare>()),
        object::id(composition),
    );
    (recording, cap, shares)
}

/// Publishes the recording by sharing it.
public fun publish<RecordingShare>(
    self: Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
) {
    let recording_id = object::id(&self);
    let composition_id = self.composition_id;
    transfer::share_object(self);
    emit(RecordingPublishedEvent<RecordingShare> { recording_id, composition_id });
}

// === View Functions ===

/// The address of the recording of `RecordingShare`. Not proof that it exists.
public fun derive_address<RecordingShare>(registry: &RecordingRegistry): address {
    derived_object::derive_address(object::id(registry), RecordingKey<RecordingShare>())
}

/// The parent composition's object ID, immutable since `new`.
public fun composition_id<RecordingShare>(self: &Recording<RecordingShare>): ID {
    self.composition_id
}

/// Read access to the recording's UID (dynamic fields).
public fun uid<RecordingShare>(self: &Recording<RecordingShare>): &UID {
    &self.id
}

// === Admin Functions ===

/// Mutable access to the recording's UID, gated by the admin cap. See
/// `composition::uid_mut` for the trust model.
public fun uid_mut<RecordingShare>(
    self: &mut Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
): &mut UID {
    &mut self.id
}

// === Private Functions ===

/// `$id` must be a direct `object::new` or `claim` call: object UIDs can't
/// be passed through a function.
macro fun new_internal<$RecordingShare>(
    $id: UID,
    $composition_id: ID,
): (Recording<$RecordingShare>, RecordingAdminCap<$RecordingShare>) {
    let mut recording = Recording<$RecordingShare> {
        id: $id,
        composition_id: $composition_id,
    };
    let cap = RecordingAdminCap<$RecordingShare> {
        id: claim(&mut recording.id, RecordingAdminCapKey()),
    };
    (recording, cap)
}

// === Test Functions ===

/// Creates a recording without a currency, for tests that don't exercise shares.
#[test_only]
public fun new_for_testing<RecordingShare>(
    composition_id: ID,
    ctx: &mut TxContext,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>) {
    new_internal!<RecordingShare>(object::new(ctx), composition_id)
}

/// Runs the real module initializer, creating and sharing the registry.
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

/// Creates an unshared registry for tests.
#[test_only]
public fun new_registry_for_testing(ctx: &mut TxContext): RecordingRegistry {
    RecordingRegistry { id: object::new(ctx) }
}

/// Unpacks a `RecordingPublishedEvent` (fields are module-private) for test assertions.
#[test_only]
public fun recording_published_event_fields<RecordingShare>(
    event: RecordingPublishedEvent<RecordingShare>,
): (ID, ID) {
    let RecordingPublishedEvent { recording_id, composition_id } = event;
    (recording_id, composition_id)
}
