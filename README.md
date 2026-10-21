# Miso Music Protocol

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

A permissionless music identity and release-consent protocol on Sui, written in Move.

Core defines compositions, recordings, and releases. Every composition and recording has one canonical share coin: a fixed supply of 100M shares covering all of the work's rights. Composition commission rates, release revenue splits, allocations, and royalty accounting belong in extensions.

## Data model

| Type | Core data |
|---|---|
| `Composition<CompositionShare>` | Identity; its share coin is the type parameter |
| `Recording<RecordingShare>` | Identity and immutable composition ID |
| `Release` | Identity, lifecycle, and ordered recording IDs |
| `ReleaseConsent` | Authorized release ID and recording ID; consumed during release creation |

Anyone can create a recording referencing an existing composition. The reference establishes a relationship; it does not establish a license or impose a commission.

## Share coins

Each work's share coin comes from its own copy of a template package in
[`templates/`](templates): `composition_share::CompositionShare` or
`recording_share::RecordingShare`. Publish the template's bytecode unchanged; only
the package address differs between works.

1. Publish the template. `init` sends the publisher a one-time, transferable
   `InitializeCurrencyTicket`.
2. `initialize_currency(&mut CoinRegistry, ticket)` registers the currency, deletes its
   metadata cap and returns the `TreasuryCap`.
3. In a later transaction, `composition::new` (or `recording::new`) consumes the
   treasury cap, mints the full supply to the caller and fixes it.

`new` aborts unless the currency matches exactly:

| Property | Composition | Recording |
|---|---|---|
| Type | `<package>::composition_share::CompositionShare` | `<package>::recording_share::RecordingShare` |
| Name | Composition Share | Recording Share |
| Symbol | `CSHARE` | `RSHARE` |
| Decimals | 6 | 6 |
| Description, icon URL | empty | empty |
| Supply | 100,000,000, fixed | 100,000,000, fixed |

It also requires the matching treasury cap, zero prior supply, an unregulated
currency and locked metadata. The checks are `share::mint` from
[misofm/share](https://github.com/misofm/share), called with the
values above. A work object is proof that its share coin passed
these checks. Consuming the treasury cap means each share type
backs exactly one work.

## Registries

`CompositionRegistry` and `RecordingRegistry` are created and shared once at
package initialization, like `ReleaseRegistry`, with no other constructor or
mutable UID access. Each work is derived from its registry under its share type
(`CompositionKey<CompositionShare>()`, `RecordingKey<RecordingShare>()`), so
`composition::derive_address<CompositionShare>(&registry)` and
`recording::derive_address<RecordingShare>(&registry)` give a work's address from
its coin type alone. Find the registries by type: there is one of each.

## Creation and authorization

```move
let (composition, composition_cap, composition_shares) = composition::new(
    &mut composition_registry, &mut composition_currency, composition_treasury_cap,
);
let (recording, recording_cap, recording_shares) = recording::new(
    &mut recording_registry, &mut recording_currency, recording_treasury_cap, &composition,
);

composition.publish(&composition_cap);
recording.publish(&recording_cap);

// The caller keeps or transfers the returned admin capabilities and shares.
```

`CompositionAdminCap<CompositionShare>` and `RecordingAdminCap<RecordingShare>`
authorize by type: there is exactly one work per share type. Each cap's address is
derived from its work. Recording creation only reads the composition, so
recordings of one composition never contend on it. `ReleaseAdminCap` stores its
release ID, readable with `release::release_id(&cap)`, and is checked by
`release::authorize`.

The admin capability represents protocol administration, not fractional economic ownership.
Capabilities are transferable bearer objects: transferring one hands over administration.
Core has no recovery authority or forced revocation mechanism.

## Extensions

Extensions attach through `uid_mut(&admin_cap)`. The matching capability is required
both before and after publication. Read-only UID access supports extension queries.

Metadata, credits, artwork, audio, and economic agreements such as a composition's
commission on its recordings live outside core. Applications requiring economic terms
must validate their recognized extension.

Extension modules control their own typed keys and APIs. Mutable UID access is a privileged
surface; extension immutability and authorization must be designed explicitly.

## Release consent

A release's ID is derived under the shared `ReleaseRegistry` from
`blake2b256(bcs(recording_ids) ‖ bcs(salt))`, where `recording_ids` is the stored
ordered `vector<ID>` and `salt` is 32 random bytes the creator shares off-chain with
the recording admins whose consent it collects. `bcs(salt)` is the length byte
`0x20` and the 32 bytes, so the salt is hashed exactly as shared, with no integer
encoding. Anyone can recompute a release's ID from its stored recording IDs and the
salt in `ReleasePublishedEvent`, and `release::derive_address` predicts it before
creation. A release holds 1 to 1,000 distinct recordings (`ENoTracks`,
`ETooManyTracks`, `EDuplicateRecording`). The cap leaves headroom under Sui's 1,024
events per transaction for anything that emits an event per track, such as
revenue distribution.

A recording admin calls `release::consent(&recording, &cap, release_id)`. It returns
a `ReleaseConsent` (`drop, store`), which extensions can wrap for offers or escrow.
Its getters expose `release_id()` and `recording_id()`.

`release::new` accepts `vector<ReleaseConsent>`, derives the release ID from the
consented recording IDs and salt, and validates and consumes every consent. It
stores only the recording IDs; consent release IDs are discarded. Only `release::new` can
unpack a consent, and `ReleaseConsent` has no `copy`.

```move
let consent = release::consent(&recording, &recording_cap, release_id);
let (release, release_cap) = release::new(&mut registry, vector[consent], salt);
release.publish(&release_cap);
```

Consent binds membership and ordering. Revenue splits, names, artwork, and other
extension data are outside that commitment. Streaming revenue is credited to each
recording by plays; a channel that sells the release as a whole, such as a
pressing, defines and collects consent for its own track split. Publication emits
the tracklist; it does not repeat consent validation.

The registry is created once during package initialization. Release creation is
permissionless, but requires the recording-admin-authorized consents.

## Lifecycle and events

Core objects are key-only and must be published in their creating transaction.
Publication shares the object and freezes its embedded relationships. Authorized
extension access remains available afterward.

An indexer can build and maintain its index of every core object from these
events and the transaction envelope alone, with no object reads or RPC calls.
Core objects have no other indexed state: each event carries every stored
field, and extension data attached through `uid_mut` is emitted by the
extension.

| Event | Fields | Max size |
|---|---|---|
| `CompositionPublishedEvent<CompositionShare>` | `composition_id: ID`, `admin_cap_id: ID` | 64 B |
| `RecordingPublishedEvent<RecordingShare>` | `recording_id: ID`, `composition_id: ID`, `admin_cap_id: ID` | 96 B |
| `ReleasePublishedEvent` | `release_id: ID`, `admin_cap_id: ID`, `recording_ids: vector<ID>`, `salt: vector<u8>` | ~32 KB |

A track's position is its index in `recording_ids`. At 1,000 tracks the release
event is about 32 KB, well under Sui's 250 KiB per-event limit. The share coin
type is the event's type parameter, and its supply is always the fixed
100,000,000 shares. Transaction metadata supplies sender and time.

Every object ID is also derivable with
`sui::derived_object::derive_address(parent_id, key)`, i.e.
`dynamic_field::hash_type_and_key(parent, DerivedObjectKey(key))`; the events
carry the work and admin cap IDs, so indexers need not compute them:

| Object | Parent | Key |
|---|---|---|
| `Composition<CompositionShare>` | `CompositionRegistry` | `CompositionKey<CompositionShare>()` |
| `CompositionAdminCap<CompositionShare>` | the composition | `CompositionAdminCapKey()` |
| `Recording<RecordingShare>` | `RecordingRegistry` | `RecordingKey<RecordingShare>()` |
| `RecordingAdminCap<RecordingShare>` | the recording | `RecordingAdminCapKey()` |
| `Release` | `ReleaseRegistry` | `ReleaseKey(blake2b256(bcs(recording_ids) ‖ bcs(salt)))` |
| `ReleaseAdminCap` | the release | `ReleaseAdminCapKey()` |

The registries are `init` singletons and emit no event; their IDs come from the
publish transaction's object effects.

## Move conventions

The package follows Sui's [Move best practices](https://docs.sui.io/develop/write-move/move-best-practices):
constructors return values, publication is separate, capabilities are object-bound,
consents are consumed by value, and tests live outside production sources.

Each module orders its sections as imports, errors, constants, structs, enums,
events (in emission order), method aliases, then functions. Structs go main
object, admin cap, registry, other value types, then derivation keys in the order
of the objects they derive.

`ReleaseConsent` lives in the release module, so only `release::new` can unpack it.
The registries are shared only by package initialization to
preserve their single namespaces.

## Dependencies

- [share](https://github.com/misofm/share): `share::mint` checks a work's
  currency against the canonical metadata and fixes its supply.

The templates are test-only dependencies. Sui framework dependencies are pinned in
`Move.lock`.

## Build and test

```sh
sui move build
sui move test
```

Tests cover the template-to-publish flow, every share currency check, extension access
after publication, lifecycle events, release derivation, and consent.

## License

[Apache 2.0](LICENSE) © Miso Labs, Inc.
