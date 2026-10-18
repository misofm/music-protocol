// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A music release: an ordered, flat tracklist with per-track revenue splits.
/// Title, cover art, credits, and disc/side grouping are presentation and
/// live in extensions. The core/extension split, atomic create-and-publish,
/// and `uid_mut` trust model are as described in `composition`.
///
/// ### Consent scope
///
/// The release id is derived under the canonical `ReleaseRegistry` from
/// `blake2b256(bcs(tracks) ‖ bcs(salt))`: the stored tracklist itself and the
/// creator's random salt, shared off-chain with the consenting recording
/// admins. A `TrackConsent` commits to that id at creation, consenting
/// to exactly the release's economics and membership and nothing else.
///
/// The id also commits to the registry's UID, so every pending consent depends
/// on that namespace staying reachable. `ReleaseRegistry` is therefore
/// created and shared exactly once at package initialization, with no
/// constructor, deletion path, or mutable UID accessor.
module musicos::release;

// === Imports ===

use sui::bcs::to_bytes;
use sui::derived_object::{Self, claim};
use sui::event::emit;
use sui::hash::blake2b256;
use bps::bps;
use musicos::track::{Self, Track, TrackConsent};

// === Errors ===

// Authorization errors (0-9)
/// The provided admin capability does not match this release.
const EUnauthorized: u64 = 0;
/// A consent targets a different release.
const EUnauthorizedAssignment: u64 = 1;

// State errors (10-19)
/// Operation requires Initialized state.
const ENotInitializedState: u64 = 10;

// Validation errors (20-29)
/// Track splits don't sum to 100% (10,000 BPS).
const EInvalidTrackSplitsSum: u64 = 20;
/// The salt is not exactly 32 bytes.
const EInvalidSaltLength: u64 = 21;

// Reference errors (50-59)
/// Release must contain at least one track.
const ENoTracks: u64 = 51;

// === Constants ===

const SALT_LENGTH: u64 = 32;

// === Structs ===

/// A music release: an ordered flat tracklist with per-track revenue splits.
public struct Release has key {
    id: UID,
    /// Current lifecycle state.
    state: ReleaseState,
    /// The ordered tracklist; same shape as the digest pre-image every
    /// track's creator consented to.
    tracks: vector<Track>,
}

/// The canonical derivation parent for every release. Its private UID is
/// reachable only by `new`, so the namespace cannot be bypassed.
public struct ReleaseRegistry has key {
    id: UID,
}

/// Key for release UID derivation.
public struct ReleaseKey(vector<u8>) has copy, drop, store;

/// Authorizes admin operations on one release.
public struct ReleaseAdminCap has key, store {
    id: UID,
    /// ID of the release this capability controls.
    release_id: ID,
}

/// Derivation key for `ReleaseAdminCap`.
public struct ReleaseAdminCapKey() has copy, drop, store;

// === Enums ===

/// Lifecycle state of a release.
public enum ReleaseState has drop, store {
    /// Created but not yet published. Carries the creator's salt, a digest
    /// input `publish` reports and cannot otherwise reach.
    Initialized {
        salt: vector<u8>,
    },
    /// Published and immutable.
    Published,
}

// === Events ===

/// Emitted once per track when a release is published, in tracklist order and
/// before the `ReleasePublishedEvent`. Together the track events are the
/// release's full allocation, duplicates and zero splits included. The
/// track's composition is not repeated: join `recording_id` to that
/// recording's `RecordingPublishedEvent`.
public struct ReleaseTrackAssignedEvent has copy, drop {
    release_id: ID,
    /// Zero-based position of the track in the tracklist.
    position: u64,
    recording_id: ID,
    split_bps: u16,
}

/// Emitted once when a release is published, after its track events:
/// identity and the creator's salt. The publish time is the event's
/// transaction timestamp. Everything else (sender, admin cap address, track
/// count, registry id, and the digest — see `release_digest`) is
/// derivable from the transaction and the same-transaction events.
public struct ReleasePublishedEvent has copy, drop {
    release_id: ID,
    salt: vector<u8>,
}

// === Public Functions ===

/// Creates and shares the one canonical registry. There is no production
/// constructor: this object is the permanent namespace every release commits to.
fun init(ctx: &mut TxContext) {
    transfer::share_object(ReleaseRegistry { id: object::new(ctx) });
}

/// Assembles a release under the canonical registry. Permissionless: consent
/// comes from recording-admin consents for this exact derived ID. Returns
/// the release and admin cap by value so `publish` can follow in the same
/// PTB. Aborts with `ENoTracks` on an empty tracklist and
/// `EInvalidTrackSplitsSum` unless splits sum to 10,000 bps; claiming an
/// already-claimed digest aborts in `derived_object`. Each consent must match
/// the derived release ID; its release ID is discarded when unwrapped.
public fun new(
    self: &mut ReleaseRegistry,
    consents: vector<TrackConsent>,
    salt: vector<u8>,
): (Release, ReleaseAdminCap) {
    assert!(!consents.is_empty(), ENoTracks);

    let mut consented_release_ids = vector[];
    let tracks = consents.map!(|consent| {
        let (release_id, track) = consent.into_parts();
        consented_release_ids.push_back(release_id);
        track
    });
    let mut split_sum = 0u64;
    tracks.do_ref!(|track| split_sum = split_sum + (track.split_bps().value() as u64));
    assert!(split_sum == (bps::denominator!() as u64), EInvalidTrackSplitsSum);

    let mut release = Release {
        id: claim(&mut self.id, ReleaseKey(release_digest(&tracks, &salt))),
        state: ReleaseState::Initialized { salt },
        tracks,
    };
    let release_id = object::id(&release);
    consented_release_ids.do!(|consented| assert!(consented == release_id, EUnauthorizedAssignment));

    let release_admin_cap = ReleaseAdminCap {
        id: claim(&mut release.id, ReleaseAdminCapKey()),
        release_id,
    };

    (release, release_admin_cap)
}

/// Publishes the release: emits one `ReleaseTrackAssignedEvent` per track,
/// shares it, and emits `ReleasePublishedEvent`. Aborts with `EUnauthorized` on a mismatched cap
/// and `ENotInitializedState` unless `Initialized`.
public fun publish(mut self: Release, cap: &ReleaseAdminCap) {
    self.authorize(cap);

    match (&self.state) {
        ReleaseState::Initialized { salt } => {
            let salt = *salt;
            self.emit_track_events();
            self.state = ReleaseState::Published;

            let release_id = object::id(&self);

            transfer::share_object(self);

            emit(ReleasePublishedEvent { release_id, salt });
        },
        _ => abort ENotInitializedState,
    }
}

/// Verifies that the admin capability matches this release.
public fun authorize(self: &Release, cap: &ReleaseAdminCap) {
    assert!(object::id(self) == cap.release_id, EUnauthorized);
}

// === View Functions ===

/// The address `new` would claim for this tracklist and salt. Not proof
/// that the release exists. Read-only registry access, so it parallelizes.
public fun derive_address(
    self: &ReleaseRegistry,
    recording_ids: vector<ID>,
    split_bps: vector<u16>,
    salt: vector<u8>,
): address {
    let tracks = recording_ids.zip_map!(split_bps, |recording_id, split| track::new(recording_id, bps::new(split)));
    derived_object::derive_address(self.id.to_inner(), ReleaseKey(release_digest(&tracks, &salt)))
}


/// The ordered tracklist — the single accessor for length, membership, and
/// per-track data.
public fun tracks(self: &Release): &vector<Track> {
    &self.tracks
}

/// Read access to the release's UID (dynamic fields).
public fun uid(self: &Release): &UID {
    &self.id
}

// === Admin Functions ===

/// Mutable access to the release's UID, gated by the admin cap. Works in any
/// lifecycle state; see `composition::uid_mut` for the trust model.
public fun uid_mut(self: &mut Release, cap: &ReleaseAdminCap): &mut UID {
    self.authorize(cap);
    &mut self.id
}

// === Private Functions ===

/// `blake2b256(bcs(tracks) ‖ bcs(salt))`, the key of the release's derived id.
/// Aborts with `EInvalidSaltLength` unless the salt is 32 bytes.
fun release_digest(tracks: &vector<Track>, salt: &vector<u8>): vector<u8> {
    assert!(salt.length() == SALT_LENGTH, EInvalidSaltLength);
    let mut hash_input = to_bytes(tracks);
    hash_input.append(to_bytes(salt));
    blake2b256(&hash_input)
}

/// Emits one `ReleaseTrackAssignedEvent` per track in tracklist order.
fun emit_track_events(self: &Release) {
    let release_id = self.id.to_inner();
    let mut position = 0;
    self.tracks.do_ref!(|track| {
        emit(ReleaseTrackAssignedEvent {
            release_id,
            position,
            recording_id: track.recording_id(),
            split_bps: track.split_bps().value(),
        });
        position = position + 1;
    });
}

// === Test Functions ===

/// Runs the real module initializer, creating and sharing the canonical registry.
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

/// Creates an unshared registry for pure validation and derivation tests.
#[test_only]
public fun new_registry_for_testing(ctx: &mut TxContext): ReleaseRegistry {
    ReleaseRegistry { id: object::new(ctx) }
}

#[test_only]
public fun release_digest_for_testing(tracks: &vector<Track>, salt: &vector<u8>): vector<u8> {
    release_digest(tracks, salt)
}

/// Unpacks a `ReleasePublishedEvent` (fields are module-private) for test assertions.
#[test_only]
public fun release_published_event_fields(
    event: ReleasePublishedEvent,
): (ID, vector<u8>) {
    let ReleasePublishedEvent { release_id, salt } = event;
    (release_id, salt)
}

// State predicates are test-only: create-and-publish is atomic, so every
// release a runtime caller can hold is `Published`.

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
public fun new_for_testing(
    consents: vector<TrackConsent>,
    ctx: &mut TxContext,
): (Release, ReleaseAdminCap) {
    // Test consents may target any release; only their tracks are kept.
    let mut release = Release {
        id: object::new(ctx),
        state: ReleaseState::Initialized { salt: vector::tabulate!(SALT_LENGTH, |_| 0) },
        tracks: consents.map!(|consent| { let (_, track) = consent.into_parts(); track }),
    };
    let release_id = object::id(&release);

    let release_admin_cap = ReleaseAdminCap {
        id: claim(&mut release.id, ReleaseAdminCapKey()),
        release_id,
    };

    (release, release_admin_cap)
}

#[test_only]
public fun release_track_assigned_event_fields(
    event: ReleaseTrackAssignedEvent,
): (ID, u64, ID, u16) {
    let ReleaseTrackAssignedEvent { release_id, position, recording_id, split_bps } = event;
    (release_id, position, recording_id, split_bps)
}
