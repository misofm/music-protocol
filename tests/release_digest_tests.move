// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Release digest and `release::derive_address`: the digest is
/// `blake2b256(bcs(vector<ID>) ‖ bcs(salt))`. Reference digests were
/// computed independently (Python `hashlib.blake2b`, digest size 32) for SDKs
/// to match.
#[test_only]
module musicos::release_digest_tests;

use std::unit_test::{assert_eq, destroy};
use sui::bcs::to_bytes;
use musicos::release;
use musicos::test_helpers;

fun id(a: address): ID { object::id_from_address(a) }

/// `vector<ID>` encodes as a ULEB128 length, then 32 bytes per recording:
/// exactly the stored tracklist.
#[test]
fun recording_ids_encode_as_stored() {
    let bytes = to_bytes(&vector[id(@0x1)]);
    assert_eq!(bytes.length(), 1 + 32);
    assert_eq!(bytes[0], 1);
    assert_eq!(bytes[32], 1);
}

/// One recording, salt of 32 `0x01` bytes.
#[test]
fun single_track_reference_digest() {
    assert_eq!(
        release::release_digest_for_testing(&vector[id(@0x1)], &test_helpers::salt(1)),
        x"7ccea1ed927c51db8b714cc0d1695c8e78d9940f75d5007d32de54c1dda3d3e6",
    );
}

/// Two recordings, salt of 32 `0x2a` bytes.
#[test]
fun two_track_reference_digest() {
    let recording_ids = vector[
        id(@0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
        id(@0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890),
    ];
    assert_eq!(
        release::release_digest_for_testing(&recording_ids, &test_helpers::salt(0x2a)),
        x"c6dc3c564f96e2a1c0e40d9fadf6e62a4415030af6fa59568c98b33a36754668",
    );
}

/// Every input changes the derived id; the same inputs always give the same id.
#[test]
fun derived_id_depends_on_every_input() {
    let mut ctx = tx_context::dummy();
    let registry = release::new_registry_for_testing(&mut ctx);
    let (a, b) = (id(@0x1), id(@0x2));

    let base = registry.derive_address(vector[a, b], test_helpers::salt(1));
    assert_eq!(base, registry.derive_address(vector[a, b], test_helpers::salt(1)));
    assert!(base != registry.derive_address(vector[a, b], test_helpers::salt(2)));
    assert!(base != registry.derive_address(vector[b, a], test_helpers::salt(1)));
    assert!(base != registry.derive_address(vector[a, b, a], test_helpers::salt(1)));
    destroy(registry);
}

#[test, expected_failure(abort_code = release::EInvalidSaltLength)]
fun short_salt_rejected() {
    release::release_digest_for_testing(&vector[id(@0x1)], &vector::tabulate!(31, |_| 0));
}

#[test, expected_failure(abort_code = release::EInvalidSaltLength)]
fun long_salt_rejected() {
    release::release_digest_for_testing(&vector[id(@0x1)], &vector::tabulate!(33, |_| 0));
}
