// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Release digest and `release::derive_address`: the digest is
/// `blake2b256(bcs(vector<Track>) ‖ bcs(salt))`. Reference digests were
/// computed independently (Python `hashlib.blake2b`, digest size 32) for SDKs
/// to match.
#[test_only]
module musicos::release_digest_tests;

use std::unit_test::{assert_eq, destroy};
use sui::bcs::to_bytes;
use bps::bps;
use musicos::release;
use musicos::test_helpers;
use musicos::track;

fun id(a: address): ID { object::id_from_address(a) }

/// `vector<Track>` encodes as a ULEB128 length, then 32 ID bytes and a 2-byte
/// little-endian split per track: exactly the stored tracklist.
#[test]
fun tracks_encode_as_stored() {
    let tracks = vector[track::new(id(@0x1), bps::new(10000))];
    let bytes = to_bytes(&tracks);
    assert_eq!(bytes.length(), 1 + 32 + 2);
    assert_eq!(bytes[0], 1);
    assert_eq!(bytes[33], 0x10); // 10000 = 0x2710, little-endian
    assert_eq!(bytes[34], 0x27);
}

/// One recording, 100%, salt of 32 `0x01` bytes.
#[test]
fun single_track_reference_digest() {
    let tracks = vector[track::new(id(@0x1), bps::new(10000))];
    assert_eq!(
        release::release_digest_for_testing(&tracks, &test_helpers::salt(1)),
        x"41d58fbc54478417e05839839cf12654a55b3a34ee2405faa4a0a7623eb52aa1",
    );
}

/// Two recordings, 50/50, salt of 32 `0x2a` bytes.
#[test]
fun two_track_reference_digest() {
    let tracks = vector[
        track::new(id(@0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef), bps::new(5000)),
        track::new(id(@0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890), bps::new(5000)),
    ];
    assert_eq!(
        release::release_digest_for_testing(&tracks, &test_helpers::salt(0x2a)),
        x"ef0e03369cafe54685e29745aae993510197d0514b5d7eb679eafc216bb4ee29",
    );
}

/// Every input changes the derived id; the same inputs always give the same id.
#[test]
fun derived_id_depends_on_every_input() {
    let mut ctx = tx_context::dummy();
    let registry = release::new_registry_for_testing(&mut ctx);
    let (a, b) = (id(@0x1), id(@0x2));

    let base = registry.derive_address(vector[a, b], vector[5000, 5000], test_helpers::salt(1));
    assert_eq!(base, registry.derive_address(vector[a, b], vector[5000, 5000], test_helpers::salt(1)));
    assert!(base != registry.derive_address(vector[a, b], vector[5000, 5000], test_helpers::salt(2)));
    assert!(base != registry.derive_address(vector[b, a], vector[5000, 5000], test_helpers::salt(1)));
    assert!(base != registry.derive_address(vector[a, b], vector[6000, 4000], test_helpers::salt(1)));
    destroy(registry);
}

#[test, expected_failure(abort_code = release::EInvalidSaltLength)]
fun short_salt_rejected() {
    let tracks = vector[track::new(id(@0x1), bps::new(10000))];
    release::release_digest_for_testing(&tracks, &vector::tabulate!(31, |_| 0));
}

#[test, expected_failure(abort_code = release::EInvalidSaltLength)]
fun long_salt_rejected() {
    let tracks = vector[track::new(id(@0x1), bps::new(10000))];
    release::release_digest_for_testing(&tracks, &vector::tabulate!(33, |_| 0));
}
