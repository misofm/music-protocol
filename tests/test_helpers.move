// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_music::test_helpers;

public struct CompositionShare() has drop;

public struct RecordingShare() has drop;

public fun fake_id(ctx: &mut TxContext): ID {
    let uid = object::new(ctx);
    let id = uid.to_inner();
    uid.delete();
    id
}
