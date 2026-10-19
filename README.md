# musicos

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

A permissionless music identity and release-consent protocol on Sui, written in Move.

Core defines compositions, recordings, and releases. Every composition and recording has one canonical share coin: a fixed supply of 100M shares covering all of the work's rights. Composition commission rates, release revenue splits, allocations, and royalty accounting belong in extensions.

## Data model

| Type | Core data |
|---|---|
| `Composition<CompositionShare>` | Identity and lifecycle; its share coin is the type parameter |
| `Recording<RecordingShare>` | Identity, lifecycle, and immutable composition ID |
| `Release` | Identity, lifecycle, and ordered recording IDs |
| `TrackConsent` | Authorized release ID and recording ID; consumed during release creation |

Anyone can create a recording referencing an existing composition. The reference establishes a relationship; it does not establish a license or impose a commission.

## Share coins

Each work's share coin comes from its own copy of a template package in
[`templates/`](templates): `composition_share::CompositionShare` or
`recording_share::RecordingShare`. Publish the template's bytecode unchanged; only
the package address differs between works.

1. Publish the template. `init` sends the publisher a one-time, transferable
   `InitializeCurrencyTicket`.
2. `initialize_currency(ticket, &mut CoinRegistry)` registers the currency, deletes its
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
(`CompositionKey<T>()`, `RecordingKey<T>()`), so
`composition::derive_address<T>(&registry)` and
`recording::derive_address<T>(&registry)` give a work's address from its coin type
alone. Find the registries by type: there is one of each.

## Creation and authorization

```move
let (composition, composition_cap, composition_shares) = composition::new(
    &mut composition_registry, &mut composition_currency, composition_treasury_cap,
);
let (recording, recording_cap, recording_shares) = recording::new(
    &mut recording_registry, &composition, &mut recording_currency, recording_treasury_cap,
);

composition.publish(&composition_cap);
recording.publish(&recording_cap);

// The caller keeps or transfers the returned admin capabilities and shares.
```

`CompositionAdminCap<CompositionShare>` and `RecordingAdminCap<RecordingShare>`
authorize by type: there is exactly one work per share type. Each cap's address is
derived from its work. Recording creation only reads the composition, so
recordings of one composition never contend on it. `ReleaseAdminCap` stores its release ID and is checked by
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
creation. A recording may appear more than once.

A recording admin calls `track::consent(&recording, &cap, release_id)`. It returns a
store-only `TrackConsent`, which extensions can wrap for offers or escrow. Its
getters expose `release_id()` and `recording_id()`.

`release::new` accepts `vector<TrackConsent>`, derives the release ID from the
consented recording IDs and salt, and validates and consumes every consent. It
stores only the recording IDs; consent release IDs are discarded. Unwrapping is
package-private, and `TrackConsent` has no `copy`.

```move
let consent = track::consent(&recording, &recording_cap, release_id);
let (release, release_cap) = release::new(&mut registry, vector[consent], salt);
release.publish(&release_cap);
```

Consent binds membership and ordering. Revenue splits, names, artwork, and other
extension data are outside that commitment. Streaming revenue is credited to each
recording by plays; a channel that sells the release as a whole, such as a
pressing, defines and collects consent for its own track split. Publication emits
the track events; it does not repeat consent validation.

The registry is created once during package initialization. Release creation is
permissionless, but requires the recording-admin-authorized consents.

## Lifecycle and events

Core objects are key-only and must be published in their creating transaction.
Publication shares the object and freezes its embedded relationships. Authorized
extension access remains available afterward.

| Event | Data |
|---|---|
| `CompositionPublishedEvent<CompositionShare>` | Composition ID |
| `RecordingPublishedEvent<RecordingShare>` | Recording ID and composition ID |
| `ReleaseTrackAssignedEvent` | Release ID, track position, recording ID |
| `ReleasePublishedEvent` | Release ID and creator salt |

Track events are emitted in tracklist order. Transaction metadata supplies sender and time.

## Move conventions

The package follows Sui's [Move best practices](https://docs.sui.io/develop/write-move/move-best-practices):
constructors return values, publication is separate, capabilities are object-bound,
consents are consumed by value, and tests live outside production sources.

`TrackConsent` lives in its own module to keep consent construction and unwrapping
encapsulated. The registries are shared only by package initialization to
preserve their single namespaces. Commit publication metadata when this source is deployed.

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
