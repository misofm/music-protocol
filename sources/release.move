// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module miso_music::release;

use miso_music::recording::Recording;
use std::u8;
use sui::{derived_object::claim, event::emit};

// === Errors ===

const EUnauthorized: u64 = 0;
const ENoTracks: u64 = 1;
const ETooManyTracks: u64 = 2;
const EDuplicateRecording: u64 = 3;

// === Structs ===

public struct Release has key {
    id: UID,
    recording_ids: vector<ID>,
}

public struct ReleaseAdminCap has key, store {
    id: UID,
    release_id: ID,
}

public struct ReleaseTrack has drop {
    recording_id: ID,
}

public struct ReleaseAdminCapKey() has copy, drop, store;

// === Events ===

public struct ReleaseCreatedEvent has copy, drop {
    release_id: ID,
    release_admin_cap_id: ID,
    recording_ids: vector<ID>,
}

// === Method Aliases ===

public use fun release_admin_cap_release_id as ReleaseAdminCap.release_id;

// === Public Functions ===

public fun new(tracks: vector<ReleaseTrack>, ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    assert!(!tracks.is_empty(), ENoTracks);
    assert!(tracks.length() <= (u8::max_value!() as u64), ETooManyTracks);
    let recording_ids = tracks.map!(|track| track.recording_id);
    let mut keys = recording_ids.map_ref!(|recording_id| recording_id.to_address().to_u256());
    keys.merge_sort_by!(|a, b| *a <= *b);
    assert!(keys.is_sorted_by!(|a, b| *a < *b), EDuplicateRecording);
    let (release, cap) = new_internal!(object::new(ctx), recording_ids);
    emit(ReleaseCreatedEvent {
        release_id: object::id(&release),
        release_admin_cap_id: object::id(&cap),
        recording_ids: release.recording_ids,
    });
    (release, cap)
}

public fun new_release_track<RecordingShare>(recording: &Recording<RecordingShare>): ReleaseTrack {
    ReleaseTrack { recording_id: object::id(recording) }
}

// === View Functions ===

public fun recording_ids(self: &Release): &vector<ID> {
    &self.recording_ids
}

public fun uid(self: &Release): &UID {
    &self.id
}

public fun release_admin_cap_release_id(cap: &ReleaseAdminCap): ID {
    cap.release_id
}

// === Admin Functions ===

public fun publish(self: Release, cap: &ReleaseAdminCap) {
    self.authorize(cap);
    transfer::share_object(self);
}

public fun uid_mut(self: &mut Release, cap: &ReleaseAdminCap): &mut UID {
    self.authorize(cap);
    &mut self.id
}

// === Private Functions ===

macro fun new_internal($id: UID, $recording_ids: vector<ID>): (Release, ReleaseAdminCap) {
    let mut release = Release { id: $id, recording_ids: $recording_ids };
    let cap = ReleaseAdminCap {
        id: claim(&mut release.id, ReleaseAdminCapKey()),
        release_id: object::id(&release),
    };
    (release, cap)
}

fun authorize(self: &Release, cap: &ReleaseAdminCap) {
    assert!(object::id(self) == cap.release_id, EUnauthorized);
}

// === Test Functions ===

#[test_only]
public fun new_for_testing(
    recording_ids: vector<ID>,
    ctx: &mut TxContext,
): (Release, ReleaseAdminCap) {
    new_internal!(object::new(ctx), recording_ids)
}

#[test_only]
public fun new_release_track_for_testing(recording_id: ID): ReleaseTrack {
    ReleaseTrack { recording_id }
}

#[test_only]
public fun release_created_fields_for_testing(event: &ReleaseCreatedEvent): (ID, ID, vector<ID>) {
    let ReleaseCreatedEvent { release_id, release_admin_cap_id, recording_ids } = event;
    (*release_id, *release_admin_cap_id, *recording_ids)
}
