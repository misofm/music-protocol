// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A recording of a composition and its canonical share coin `RecordingShare`.
/// Creation consumes the coin's treasury cap, so each share type backs exactly
/// one recording, and the 100M fixed supply goes to the creator. The parent
/// composition ID freezes at creation. Extensions attach through
/// admin-authorized UID access. Objects are key-only: creation must end with
/// publication in the same transaction.
module musicos::recording;

// === Imports ===

use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::Currency;
use sui::derived_object::claim;
use sui::event::emit;

#[test_only]
use sui::bcs::to_bytes;

use share::share::{Self, Spec};

use musicos::composition::Composition;

// === Errors ===

// State errors (10-19)
/// Operation requires Initialized state but recording is in a different state.
const ENotInitializedState: u64 = 10;

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
    /// Current lifecycle state.
    state: RecordingState,
    /// The parent composition identity.
    composition_id: ID,
}

/// Authorizes admin operations on the one recording of its share type.
/// Its address is derived from the recording under `RecordingAdminCapKey`.
public struct RecordingAdminCap<phantom RecordingShare> has key, store {
    id: UID,
}

/// Derivation key for `RecordingAdminCap`.
public struct RecordingAdminCapKey() has copy, drop, store;

// === Enums ===

/// Lifecycle state of a recording.
public enum RecordingState has drop, store {
    /// Created but not yet published.
    Initialized,
    /// Published and immutable.
    Published,
}

// === Events ===

/// Emitted once when the recording is published.
public struct RecordingPublishedEvent<phantom RecordingShare> has copy, drop {
    recording_id: ID,
    composition_id: ID,
}

// === Public Functions ===

/// Creates a recording of `composition` and its admin cap from a fresh
/// `<package>::recording_share::RecordingShare` currency, returning the full
/// share supply. The currency must satisfy `share_spec`.
public fun new<RecordingShare: key, CompositionShare>(
    composition: &Composition<CompositionShare>,
    currency: &mut Currency<RecordingShare>,
    treasury_cap: TreasuryCap<RecordingShare>,
    ctx: &mut TxContext,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>, Balance<RecordingShare>) {
    let shares = share::mint(currency, treasury_cap, &share_spec());
    let (recording, cap) = new_internal(object::id(composition), ctx);
    (recording, cap, shares)
}

/// Publishes the recording: shares it and freezes its embedded fields.
/// Aborts with `ENotInitializedState` unless `Initialized`.
public fun publish<RecordingShare>(
    mut self: Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
) {
    match (&self.state) {
        RecordingState::Initialized => {
            self.state = RecordingState::Published;
            let recording_id = object::id(&self);
            let composition_id = self.composition_id;
            transfer::share_object(self);
            emit(RecordingPublishedEvent<RecordingShare> { recording_id, composition_id });
        },
        _ => abort ENotInitializedState,
    }
}

// === View Functions ===

/// The parent composition's object ID, immutable since `new`.
public fun composition_id<RecordingShare>(self: &Recording<RecordingShare>): ID {
    self.composition_id
}

/// Read access to the recording's UID (dynamic fields).
public fun uid<RecordingShare>(self: &Recording<RecordingShare>): &UID {
    &self.id
}

/// The canonical recording share coin: `<package>::recording_share::RecordingShare`,
/// 6 decimals, "Recording Share", `RSHARE`, empty description and icon,
/// 100M fixed supply. `share::is_share` checks a currency against it.
public fun share_spec(): Spec {
    share::spec(
        SHARE_MODULE,
        SHARE_DATATYPE,
        SHARE_DECIMALS,
        SHARE_NAME.to_string(),
        SHARE_SYMBOL.to_string(),
        b"".to_string(),
        b"".to_string(),
        SHARE_SUPPLY,
    )
}

// === Admin Functions ===

/// Mutable access to the recording's UID, gated by the admin cap. Works in
/// any lifecycle state; see `composition::uid_mut` for the trust model.
public fun uid_mut<RecordingShare>(
    self: &mut Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
): &mut UID {
    &mut self.id
}

// === Private Functions ===

fun new_internal<RecordingShare>(
    composition_id: ID,
    ctx: &mut TxContext,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>) {
    let mut recording = Recording<RecordingShare> {
        id: object::new(ctx),
        state: RecordingState::Initialized,
        composition_id,
    };
    let cap = RecordingAdminCap<RecordingShare> {
        id: claim(&mut recording.id, RecordingAdminCapKey()),
    };
    (recording, cap)
}

// === Test Functions ===

// State predicates are test-only: create-and-publish is atomic, so every
// recording a runtime caller can hold is `Published`.

#[test_only]
public fun is_initialized_state<RecordingShare>(self: &Recording<RecordingShare>): bool {
    match (&self.state) { RecordingState::Initialized => true, _ => false }
}

#[test_only]
public fun is_published_state<RecordingShare>(self: &Recording<RecordingShare>): bool {
    match (&self.state) { RecordingState::Published => true, _ => false }
}

#[test_only]
public fun published_state_bcs_bytes(): vector<u8> {
    to_bytes(&RecordingState::Published)
}

/// Creates a recording without a currency, for tests that don't exercise shares.
#[test_only]
public fun new_for_testing<RecordingShare>(
    composition_id: ID,
    ctx: &mut TxContext,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>) {
    new_internal(composition_id, ctx)
}

/// Unpacks a `RecordingPublishedEvent` (fields are module-private) for test assertions.
#[test_only]
public fun recording_published_event_fields<RecordingShare>(
    event: RecordingPublishedEvent<RecordingShare>,
): (ID, ID) {
    let RecordingPublishedEvent { recording_id, composition_id } = event;
    (recording_id, composition_id)
}
