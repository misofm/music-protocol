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

/// One recording, 100%, salt 1.
#[test]
fun single_track_reference_digest() {
    let tracks = vector[track::new(id(@0x1), bps::new(10000))];
    assert_eq!(
        release::release_digest_for_testing(&tracks, 1),
        x"318fc24c1aba9259b2b457924a1d93fe1b5d5b228ed3b3b8296b14969bf87200",
    );
}

/// Two recordings, 50/50, salt 42.
#[test]
fun two_track_reference_digest() {
    let tracks = vector[
        track::new(id(@0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef), bps::new(5000)),
        track::new(id(@0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890), bps::new(5000)),
    ];
    assert_eq!(
        release::release_digest_for_testing(&tracks, 42),
        x"322a0c595bbeff96b9f0744019478c89861ff8ca2852e2460a583f9d75b8238f",
    );
}

/// Every input changes the derived id; the same inputs always give the same id.
#[test]
fun derived_id_depends_on_every_input() {
    let mut ctx = tx_context::dummy();
    let registry = release::new_registry_for_testing(&mut ctx);
    let (a, b) = (id(@0x1), id(@0x2));

    let base = registry.derive_address(vector[a, b], vector[5000, 5000], 1);
    assert_eq!(base, registry.derive_address(vector[a, b], vector[5000, 5000], 1));
    assert!(base != registry.derive_address(vector[a, b], vector[5000, 5000], 2));
    assert!(base != registry.derive_address(vector[b, a], vector[5000, 5000], 1));
    assert!(base != registry.derive_address(vector[a, b], vector[6000, 4000], 1));
    destroy(registry);
}
