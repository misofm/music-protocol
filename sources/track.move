// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Explicit recording-admin consent to place a recording on one release.
module musicos::track;

// === Imports ===

use musicos::recording::{Recording, RecordingAdminCap};

// === Structs ===

/// Recording-admin consent to include a recording in one specific release.
/// Extensions may wrap consent for offers or escrow before release creation.
public struct TrackConsent has drop, store {
    /// The exact release identity authorized by the recording admin.
    release_id: ID,
    /// The recording committed to by this consent.
    recording_id: ID,
}

// === Public Functions ===

/// Consents to inclusion in a release, authorized by the recording's admin
/// cap. Consent may be discarded or stored by an extension; release creation
/// consumes it without retaining its release ID.
public fun consent<RecordingShare>(
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
    release_id: ID,
): TrackConsent {
    TrackConsent { release_id, recording_id: object::id(recording) }
}

// === View Functions ===

/// The release authorized by this consent.
public fun release_id(self: &TrackConsent): ID {
    self.release_id
}

/// The recording committed to by this consent.
public fun recording_id(self: &TrackConsent): ID {
    self.recording_id
}

// === Package Functions ===

/// Consumes consent, returning the consented release ID and recording ID.
public(package) fun into_parts(self: TrackConsent): (ID, ID) {
    let TrackConsent { release_id, recording_id } = self;
    (release_id, recording_id)
}

// === Test Functions ===

#[test_only]
public fun consent_for_testing(recording_id: ID, release_id: ID): TrackConsent {
    TrackConsent { release_id, recording_id }
}
