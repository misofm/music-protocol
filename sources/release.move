// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A music release: an ordered, flat tracklist of recordings. Title, cover
/// art, credits, disc/side grouping, and revenue splits live in extensions.
/// The core/extension boundary, atomic create-and-publish, and `uid_mut`
/// trust model are as described in `composition`.
///
/// ### Consent scope
///
/// The release id is derived under the canonical `ReleaseRegistry` from
/// `blake2b256(bcs(recording_ids) ‖ bcs(salt))`: the stored tracklist itself
/// and the creator's random salt, shared off-chain with the consenting
/// recording admins. A `ReleaseConsent` commits to that id at creation,
/// consenting to exactly the release's membership and order and nothing else.
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
use musicos::recording::{Recording, RecordingAdminCap};

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
/// The salt is not exactly 32 bytes.
const EInvalidSaltLength: u64 = 21;
/// A recording appears more than once in the tracklist.
const EDuplicateRecording: u64 = 22;
/// The tracklist exceeds `MAX_TRACKS`.
const ETooManyTracks: u64 = 23;

// Reference errors (50-59)
/// Release must contain at least one track.
const ENoTracks: u64 = 51;

// === Constants ===

const SALT_LENGTH: u64 = 32;
/// Leaves headroom under Sui's 1,024 events per transaction for anything that
/// emits an event per track, such as publication and revenue distribution.
const MAX_TRACKS: u64 = 1_000;

// === Structs ===

/// A music release: an ordered flat tracklist of recordings.
public struct Release has key {
    id: UID,
    /// Current lifecycle state.
    state: ReleaseState,
    /// The ordered tracklist of distinct recordings; the digest pre-image
    /// every track's recording admin consented to.
    recording_ids: vector<ID>,
}

/// Authorizes admin operations on one release.
public struct ReleaseAdminCap has key, store {
    id: UID,
    /// ID of the release this capability controls.
    release_id: ID,
}

/// The canonical derivation parent for every release. Its private UID is
/// reachable only by `new`, so the namespace cannot be bypassed.
public struct ReleaseRegistry has key {
    id: UID,
}

/// Recording-admin consent to include a recording in one specific release.
/// Extensions may wrap consent for offers or escrow before release creation.
public struct ReleaseConsent has drop, store {
    /// The exact release identity authorized by the recording admin.
    release_id: ID,
    /// The recording committed to by this consent.
    recording_id: ID,
}

/// Key for release UID derivation.
public struct ReleaseKey(vector<u8>) has copy, drop, store;

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
/// release's full tracklist. The track's composition
/// is not repeated: join `recording_id` to that recording's
/// `RecordingPublishedEvent`.
public struct ReleaseTrackAssignedEvent has copy, drop {
    release_id: ID,
    /// Zero-based position of the track in the tracklist.
    position: u64,
    recording_id: ID,
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

// === Method Aliases ===

public use fun consent_release_id as ReleaseConsent.release_id;
public use fun consent_recording_id as ReleaseConsent.recording_id;

// === Public Functions ===

/// Creates and shares the one canonical registry. There is no production
/// constructor: this object is the permanent namespace every release commits to.
fun init(ctx: &mut TxContext) {
    transfer::share_object(ReleaseRegistry { id: object::new(ctx) });
}

/// Consents to including the recording in a release, authorized by the
/// recording's admin cap. Consent may be discarded or stored by an
/// extension; `new` consumes it without retaining its release ID.
public fun consent<RecordingShare>(
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
    release_id: ID,
): ReleaseConsent {
    ReleaseConsent { release_id, recording_id: object::id(recording) }
}

/// Assembles a release under the canonical registry. Permissionless: consent
/// comes from recording-admin consents for this exact derived ID. Returns
/// the release and admin cap by value so `publish` can follow in the same
/// PTB. Aborts with `ENoTracks` on an empty tracklist, `ETooManyTracks`
/// above `MAX_TRACKS` and `EDuplicateRecording` if a recording repeats;
/// claiming an already-claimed digest aborts in `derived_object`. Each consent must match
/// the derived release ID; its release ID is discarded when unwrapped.
public fun new(
    self: &mut ReleaseRegistry,
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
    assert_distinct(&recording_ids);

    let mut release = Release {
        id: claim(&mut self.id, ReleaseKey(release_digest(&recording_ids, &salt))),
        state: ReleaseState::Initialized { salt },
        recording_ids,
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
    salt: vector<u8>,
): address {
    derived_object::derive_address(self.id.to_inner(), ReleaseKey(release_digest(&recording_ids, &salt)))
}

/// The release authorized by a consent.
public fun consent_release_id(consent: &ReleaseConsent): ID {
    consent.release_id
}

/// The recording committed to by a consent.
public fun consent_recording_id(consent: &ReleaseConsent): ID {
    consent.recording_id
}

/// The ordered tracklist of recording IDs.
public fun recording_ids(self: &Release): &vector<ID> {
    &self.recording_ids
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

/// Aborts with `EDuplicateRecording` if a recording ID repeats. Sorts a copy,
/// so the cost grows as n log n rather than n².
fun assert_distinct(recording_ids: &vector<ID>) {
    let mut keys = recording_ids.map_ref!(|id| id.to_address().to_u256());
    keys.merge_sort_by!(|a, b| *a <= *b);
    let mut i = 1;
    while (i < keys.length()) {
        assert!(keys[i - 1] != keys[i], EDuplicateRecording);
        i = i + 1;
    };
}

/// `blake2b256(bcs(recording_ids) ‖ bcs(salt))`, the key of the release's
/// derived id. Aborts with `EInvalidSaltLength` unless the salt is 32 bytes.
fun release_digest(recording_ids: &vector<ID>, salt: &vector<u8>): vector<u8> {
    assert!(salt.length() == SALT_LENGTH, EInvalidSaltLength);
    let mut hash_input = to_bytes(recording_ids);
    hash_input.append(to_bytes(salt));
    blake2b256(&hash_input)
}

/// Emits one `ReleaseTrackAssignedEvent` per track in tracklist order.
fun emit_track_events(self: &Release) {
    let release_id = self.id.to_inner();
    let mut position = 0;
    self.recording_ids.do_ref!(|recording_id| {
        emit(ReleaseTrackAssignedEvent { release_id, position, recording_id: *recording_id });
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
public fun release_digest_for_testing(recording_ids: &vector<ID>, salt: &vector<u8>): vector<u8> {
    release_digest(recording_ids, salt)
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
    // Test consents may target any release; only their recordings are kept.
    let mut release = Release {
        id: object::new(ctx),
        state: ReleaseState::Initialized { salt: vector::tabulate!(SALT_LENGTH, |_| 0) },
        recording_ids: consents.map!(|consent| { let ReleaseConsent { release_id: _, recording_id } = consent; recording_id }),
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
): (ID, u64, ID) {
    let ReleaseTrackAssignedEvent { release_id, position, recording_id } = event;
    (release_id, position, recording_id)
}
