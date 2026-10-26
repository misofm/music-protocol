// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module miso_music::release;

// === Imports ===

use std::u8;
use sui::derived_object::claim;
use sui::event::emit;
use miso_music::recording::Recording;

// === Errors ===

const EUnauthorized: u64 = 0;
const EDuplicateRecording: u64 = 1;
const ETooManyTracks: u64 = 2;
const ENoTracks: u64 = 3;

// === Structs ===

public struct Release has key {
    id: UID,
    tracks: vector<ReleaseTrack>,
}

public struct ReleaseAdminCap has key, store {
    id: UID,
    release_id: ID,
}

public struct ReleaseTrack has drop, store {
    recording_id: ID,
}

public struct ReleaseAdminCapKey() has copy, drop, store;

// === Events ===

public struct ReleasePublishedEvent has copy, drop {
    release_id: ID,
    admin_cap_id: ID,
    recording_ids: vector<ID>,
}

// === Method Aliases ===

public use fun release_admin_cap_release_id as ReleaseAdminCap.release_id;
public use fun release_track_recording_id as ReleaseTrack.recording_id;

// === Public Functions ===

public fun new_release_track<RecordingShare>(recording: &Recording<RecordingShare>): ReleaseTrack {
    ReleaseTrack { recording_id: object::id(recording) }
}

public fun new(tracks: vector<ReleaseTrack>, ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    assert!(!tracks.is_empty(), ENoTracks);
    assert!(tracks.length() <= (u8::max_value!() as u64), ETooManyTracks);

    let mut keys = tracks.map_ref!(|track| track.recording_id.to_address().to_u256());
    keys.merge_sort_by!(|a, b| *a <= *b);
    assert!(keys.is_sorted_by!(|a, b| *a < *b), EDuplicateRecording);

    let mut release = Release { id: object::new(ctx), tracks };
    let release_id = object::id(&release);
    let release_admin_cap = ReleaseAdminCap {
        id: claim(&mut release.id, ReleaseAdminCapKey()),
        release_id,
    };

    (release, release_admin_cap)
}

// === View Functions ===

public fun tracks(self: &Release): &vector<ReleaseTrack> {
    &self.tracks
}

public fun uid(self: &Release): &UID {
    &self.id
}

public fun release_admin_cap_release_id(cap: &ReleaseAdminCap): ID {
    cap.release_id
}

public fun release_track_recording_id(track: &ReleaseTrack): ID {
    track.recording_id
}

// === Admin Functions ===

public fun publish(self: Release, cap: &ReleaseAdminCap) {
    self.authorize(cap);
    let release_id = object::id(&self);
    let recording_ids = self.tracks.map_ref!(|track| track.recording_id);
    transfer::share_object(self);
    emit(ReleasePublishedEvent { release_id, admin_cap_id: object::id(cap), recording_ids });
}

public fun authorize(self: &Release, cap: &ReleaseAdminCap) {
    assert!(object::id(self) == cap.release_id, EUnauthorized);
}

public fun uid_mut(self: &mut Release, cap: &ReleaseAdminCap): &mut UID {
    self.authorize(cap);
    &mut self.id
}

// === Test Functions ===

#[test_only]
public fun new_for_testing(
    recording_ids: vector<ID>,
    ctx: &mut TxContext,
): (Release, ReleaseAdminCap) {
    let mut release = Release {
        id: object::new(ctx),
        tracks: recording_ids.map!(|recording_id| ReleaseTrack { recording_id }),
    };
    let release_id = object::id(&release);
    let release_admin_cap = ReleaseAdminCap {
        id: claim(&mut release.id, ReleaseAdminCapKey()),
        release_id,
    };
    (release, release_admin_cap)
}

#[test_only]
public fun release_track_for_testing(recording_id: ID): ReleaseTrack {
    ReleaseTrack { recording_id }
}

#[test_only]
public fun release_published_event_fields(
    event: ReleasePublishedEvent,
): (ID, ID, vector<ID>) {
    let ReleasePublishedEvent { release_id, admin_cap_id, recording_ids } = event;
    (release_id, admin_cap_id, recording_ids)
}

#[test_only]
public fun max_tracks(): u64 { u8::max_value!() as u64 }
