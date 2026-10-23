// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module miso_music::release;

// === Imports ===

use sui::bcs::to_bytes;
use sui::derived_object::{Self, claim};
use sui::event::emit;
use sui::hash::blake2b256;
use miso_music::recording::{Recording, RecordingAdminCap};

// === Errors ===

const EUnauthorized: u64 = 0;
const EUnauthorizedAssignment: u64 = 1;
const ENotInitializedState: u64 = 2;
const EInvalidSaltLength: u64 = 3;
const EDuplicateRecording: u64 = 4;
const ETooManyTracks: u64 = 5;
const ENoTracks: u64 = 6;

// === Constants ===

const SALT_LENGTH: u64 = 32;
const MAX_TRACKS: u64 = 1_000;

// === Structs ===

public struct Release has key {
    id: UID,
    state: ReleaseState,
    recording_ids: vector<ID>,
}

public struct ReleaseAdminCap has key, store {
    id: UID,
    release_id: ID,
}

public struct ReleaseRegistry has key {
    id: UID,
}

public struct ReleaseConsent has drop, store {
    release_id: ID,
    recording_id: ID,
}

public struct ReleaseKey(vector<u8>) has copy, drop, store;

public struct ReleaseAdminCapKey() has copy, drop, store;

// === Enums ===

public enum ReleaseState has drop, store {
    Initialized {
        salt: vector<u8>,
    },
    Published,
}

// === Events ===

public struct ReleasePublishedEvent has copy, drop {
    release_id: ID,
    admin_cap_id: ID,
    recording_ids: vector<ID>,
    salt: vector<u8>,
}

// === Method Aliases ===

public use fun release_admin_cap_release_id as ReleaseAdminCap.release_id;
public use fun release_consent_release_id as ReleaseConsent.release_id;
public use fun release_consent_recording_id as ReleaseConsent.recording_id;

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(ReleaseRegistry { id: object::new(ctx) });
}

public fun new(
    registry: &mut ReleaseRegistry,
    consents: vector<ReleaseConsent>,
    salt: vector<u8>,
): (Release, ReleaseAdminCap) {
    assert!(!consents.is_empty(), ENoTracks);
    assert!(consents.length() <= MAX_TRACKS, ETooManyTracks);

    let mut consented_release_ids = vector[];
    let recording_ids = consents.map!(|consent| {
        let ReleaseConsent { release_id, recording_id } = consent;
        consented_release_ids.push_back(release_id);
        recording_id
    });
    let mut keys = recording_ids.map_ref!(|id| id.to_address().to_u256());
    keys.merge_sort_by!(|a, b| *a <= *b);
    assert!(keys.is_sorted_by!(|a, b| *a < *b), EDuplicateRecording);

    let mut release = Release {
        id: claim(&mut registry.id, ReleaseKey(release_digest(&recording_ids, &salt))),
        state: ReleaseState::Initialized { salt },
        recording_ids,
    };
    let release_id = object::id(&release);
    consented_release_ids.do!(|consented| {
        assert!(consented == release_id, EUnauthorizedAssignment)
    });

    let release_admin_cap = ReleaseAdminCap {
        id: claim(&mut release.id, ReleaseAdminCapKey()),
        release_id,
    };

    (release, release_admin_cap)
}

// === View Functions ===

public fun derive_address(
    registry: &ReleaseRegistry,
    recording_ids: vector<ID>,
    salt: vector<u8>,
): address {
    derived_object::derive_address(
        registry.id.to_inner(),
        ReleaseKey(release_digest(&recording_ids, &salt)),
    )
}

public fun recording_ids(self: &Release): &vector<ID> {
    &self.recording_ids
}

public fun uid(self: &Release): &UID {
    &self.id
}

public fun authorize(self: &Release, cap: &ReleaseAdminCap) {
    assert!(object::id(self) == cap.release_id, EUnauthorized);
}

public fun release_admin_cap_release_id(cap: &ReleaseAdminCap): ID {
    cap.release_id
}

public fun release_consent_release_id(consent: &ReleaseConsent): ID {
    consent.release_id
}

public fun release_consent_recording_id(consent: &ReleaseConsent): ID {
    consent.recording_id
}

// === Admin Functions ===

public fun consent<RecordingShare>(
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
    release_id: ID,
): ReleaseConsent {
    ReleaseConsent { release_id, recording_id: object::id(recording) }
}

public fun publish(mut self: Release, cap: &ReleaseAdminCap) {
    self.authorize(cap);

    match (&self.state) {
        ReleaseState::Initialized { salt } => {
            let salt = *salt;
            self.state = ReleaseState::Published;

            let release_id = object::id(&self);
            let recording_ids = self.recording_ids;

            transfer::share_object(self);

            emit(ReleasePublishedEvent {
                release_id,
                admin_cap_id: object::id(cap),
                recording_ids,
                salt,
            });
        },
        _ => abort ENotInitializedState,
    }
}

public fun uid_mut(self: &mut Release, cap: &ReleaseAdminCap): &mut UID {
    self.authorize(cap);
    &mut self.id
}

// === Private Functions ===

fun release_digest(recording_ids: &vector<ID>, salt: &vector<u8>): vector<u8> {
    assert!(salt.length() == SALT_LENGTH, EInvalidSaltLength);
    let mut hash_input = to_bytes(recording_ids);
    hash_input.append(to_bytes(salt));
    blake2b256(&hash_input)
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun new_registry_for_testing(ctx: &mut TxContext): ReleaseRegistry {
    ReleaseRegistry { id: object::new(ctx) }
}

#[test_only]
public fun release_digest_for_testing(
    recording_ids: &vector<ID>,
    salt: &vector<u8>,
): vector<u8> {
    release_digest(recording_ids, salt)
}

#[test_only]
public fun release_published_event_fields(
    event: ReleasePublishedEvent,
): (ID, ID, vector<ID>, vector<u8>) {
    let ReleasePublishedEvent { release_id, admin_cap_id, recording_ids, salt } = event;
    (release_id, admin_cap_id, recording_ids, salt)
}

#[test_only]
public fun is_initialized_state(self: &Release): bool {
    match (&self.state) {
        ReleaseState::Initialized { .. } => true,
        _ => false,
    }
}

#[test_only]
public fun is_published_state(self: &Release): bool {
    match (&self.state) {
        ReleaseState::Published => true,
        _ => false,
    }
}

#[test_only]
public fun published_state_bcs_bytes(): vector<u8> {
    to_bytes(&ReleaseState::Published)
}

#[test_only]
public fun max_tracks(): u64 { MAX_TRACKS }

#[test_only]
public fun consent_for_testing(recording_id: ID, release_id: ID): ReleaseConsent {
    ReleaseConsent { release_id, recording_id }
}

#[test_only]
public fun new_for_testing(
    consents: vector<ReleaseConsent>,
    ctx: &mut TxContext,
): (Release, ReleaseAdminCap) {
    let mut release = Release {
        id: object::new(ctx),
        state: ReleaseState::Initialized { salt: vector::tabulate!(SALT_LENGTH, |_| 0) },
        recording_ids: consents.map!(|consent| {
            let ReleaseConsent { release_id: _, recording_id } = consent;
            recording_id
        }),
    };
    let release_id = object::id(&release);

    let release_admin_cap = ReleaseAdminCap {
        id: claim(&mut release.id, ReleaseAdminCapKey()),
        release_id,
    };

    (release, release_admin_cap)
}
