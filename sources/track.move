// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A recording placed on a release with a revenue split and explicit
/// recording-admin consent to the target release identity.
module musicos::track;

// === Imports ===

use bps::bps::{Self, BPS};
use musicos::recording::{Recording, RecordingAdminCap};

// === Structs ===

/// A recording on a release with its revenue split.
public struct Track has drop, store {
    /// The recording on this track and the routing target for its revenue.
    recording_id: ID,
    /// This track's share of the release's revenue. All tracks in a release
    /// sum to 100%; downstream allocations belong to extensions.
    split_bps: BPS,
}

/// Recording-admin consent to include a track in one specific release.
/// Extensions may wrap consent for offers or escrow before release creation.
public struct TrackConsent has drop, store {
    /// The exact release identity authorized by the recording admin.
    release_id: ID,
    /// The recording and split committed to by this consent.
    track: Track,
}

// === Method Aliases ===

public use fun track_consent_release_id as TrackConsent.release_id;
public use fun track_consent_track as TrackConsent.track;

// === Public Functions ===

/// Consents to inclusion in a release at the given split, authorized by the
/// recording's admin cap. Consent may be discarded or stored by an extension;
/// release creation consumes it without retaining its ID.
public fun consent<RecordingShare>(
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
    release_id: ID,
    split_bps: u16,
): TrackConsent {
    TrackConsent {
        release_id,
        track: Track {
            recording_id: object::id(recording),
            split_bps: bps::new(split_bps),
        },
    }
}

// === View Functions ===

/// Returns the ID of the recording.
public fun recording_id(self: &Track): ID {
    self.recording_id
}

/// Returns this track's share of the release's revenue (in basis points).
public fun split_bps(self: &Track): BPS {
    self.split_bps
}

/// The release authorized by this consent.
public fun track_consent_release_id(consent: &TrackConsent): ID { consent.release_id }

/// Read-only access to the consented recording and split.
public fun track_consent_track(consent: &TrackConsent): &Track { &consent.track }

// === Package Functions ===

/// Builds a bare track, for release ID derivation.
public(package) fun new(recording_id: ID, split_bps: BPS): Track {
    Track { recording_id, split_bps }
}

/// Consumes consent, returning the consented release ID and the track.
public(package) fun into_parts(self: TrackConsent): (ID, Track) {
    let TrackConsent { release_id, track } = self;
    (release_id, track)
}

// === Test Functions ===

#[test_only]
public fun consent_for_testing(
    recording_id: ID,
    release_id: ID,
    split_bps: u16,
): TrackConsent {
    TrackConsent {
        release_id,
        track: Track { recording_id, split_bps: bps::new(split_bps) },
    }
}
