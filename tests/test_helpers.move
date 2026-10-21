// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::test_helpers;

/// Phantom share type for compositions created without a currency.
public struct CompositionShare() has drop;
/// Phantom share type for recordings created without a currency.
public struct RecordingShare() has drop;

/// Creates a fake ID for testing by creating and immediately deleting a UID.
public fun fake_id(ctx: &mut TxContext): ID {
    let uid = object::new(ctx);
    let id = uid.to_inner();
    uid.delete();
    id
}

/// A 32-byte release salt with every byte set to `byte`.
public fun salt(byte: u8): vector<u8> {
    vector::tabulate!(32, |_| byte)
}
