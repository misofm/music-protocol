#[test_only]
module musicos::test_helpers;

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
