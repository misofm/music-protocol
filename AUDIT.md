# Security Audit — `music-protocol`

Audited at `1538d77035c4fb6b45b74f7d85168b7c3a80564b` (2026-10-21). Covers the `miso_music`
package (`composition`, `recording`, `release`), the share templates
`templates/composition_share` and `templates/recording_share`, and the pinned dependency
`share::share::mint` (misofm/share `4cdd365`) that core's currency checks rely on. Later commits
inline `assert_distinct` into `release::new`, rename and reorder getters, add method aliases and
apply naming and ordering standards. The commit "Let anyone create a release from Track proofs"
(2026-10-24) then removed the release consent layer: `ReleaseConsent`, the release registry, the
salt, the derived release ID and `ReleaseState`. Every statement about `release` below was
re-checked against that code. Line references are to the current code.

## What it does

Identity core: one `Composition<CompositionShare>` and one `Recording<RecordingShare>` per
share coin type, each backed by a fixed 100M-share currency, and `Release` objects holding an
ordered tracklist of `ReleaseTrack` values that anyone can create from existing recordings. See
[README](README.md).

## Trust model

- **Anyone** may publish a share template, register its currency, create a composition or
  recording (`composition::new`, `recording::new`), create a release of any recordings
  (`release::new_release_track`, `release::new`), and read every object (`uid`, `derive_address`,
  getters).
- **Share package publisher** holds `InitializeCurrencyTicket` (`key, store`, transferable);
  it is the only path to `coin_registry::new_currency<T>` for that type because the Sui
  verifier rejects `new_currency` on a type from another module (checked: a probe calling it
  with a foreign type fails to build with `ESC02010`).
- **`TreasuryCap<T>` holder** is the only party who can create the work for `T`;
  `share::mint` consumes the cap and fixes supply, so there is at most one work per type and
  no later minting (`share.move:31-61`).
- **`CompositionAdminCap<T>` / `RecordingAdminCap<T>` holder** (bearer, `key, store`): can
  publish the work and obtain `&mut UID` at any time (`composition.move:106-111`,
  `recording.move:113-118`). A recording admin has no say over which releases include the
  recording. Authorization is by type parameter: exactly one work and one cap
  exist per `T`, both derived (`composition.move:76-78,115-123`, `recording.move:76-79,122-134`).
- **`ReleaseAdminCap` holder** (bearer, `key, store`): can publish the release and obtain
  `&mut UID`; checked by stored `release_id` (`release.move:96-97,105-112`).
- **Package upgrader** (holder of the `UpgradeCap`): can add functions that claim new keys
  under the two registries, construct `ReleaseTrack` values without a recording, or expose `&mut UID`
  without a cap. Core has no on-chain
  defence against this; see Operational requirements.
- **Nobody** can: construct a registry after `init` (`composition.move:51-53`,
  `recording.move:54-56`); mutate a registry UID; change `Recording.composition_id` or
  `Release.recording_ids`; construct a `ReleaseTrack` except from a `&Recording` (`release.move:72-74`); mint
  shares after creation; re-regulate or edit the currency metadata
  (metadata cap deleted; `make_regulated` is initializer-only and no `DenyCapV2<T>` can
  exist for a `key` type); delete a work, release or cap; or recover a lost cap.

## Findings

**MP-1 · Low · Accepted** — Composition and recording `publish` is repeatable. `publish`
takes the object by value and calls `transfer::share_object`
(`composition.move:94-104`, `recording.move:99-111`); Sui allows re-sharing an already shared
object, so the cap holder can call `publish` again on the shared object and emit a second
`CompositionPublishedEvent` / `RecordingPublishedEvent` with identical fields. Verified in a
`test_scenario` probe (second tx: one user event, no abort). No state changes; the state enum
that prevented this was removed deliberately (`f613a89`). Indexers must dedupe by object ID.
Release `publish` is repeatable the same way since `ReleaseState` was removed
(`release.move:96-103`): a second `ReleasePublishedEvent` with identical fields
(`release_publish_twice_emits_again`).

**MP-3 · Info · Accepted** — Core verifies the currency, not the template bytecode.
`share::is_type` matches only `<any address>::composition_share::CompositionShare` /
`::recording_share::RecordingShare` (`share.move:65-73`); a hand-written package with that
module and struct name passes (the test fixture `miso_music::composition_share` does). All
core guarantees (locked metadata, unregulated, exact metadata, zero prior supply, matching
treasury cap, fixed supply) are checked on `Currency<T>` and the consumed `TreasuryCap<T>`,
so they hold regardless of the bytecode. The README's "publish the template unchanged" is
tooling guidance, not an on-chain property.

**MP-4 · Info · Open** — `ReleaseAdminCap.release_id` is stored although the cap ID is derived
from the release (`release.move:27-30,64-67`). `authorize` could compare
`derived_object::derive_address(object::id(release), ReleaseAdminCapKey())` with the cap ID
instead. Storage-only; no security impact.

**MP-6 · Info · Open** — Composition and recording creations serialize on one shared registry
per kind (`composition.move:56`, `recording.move:59`). Throughput of `composition::new` and
`recording::new` is bounded by consensus sequencing of that object. `derive_address` reads
only. `release::new` touches no shared object: it reads each recording immutably through
`new_release_track` and creates the release with `object::new`.

**MP-7 · Info · Open** — Works, releases and all three admin caps have no deletion path;
storage deposits are permanent and a cap can only be retired by transferring it to an
unusable address.

## Checked, no finding

- **One work per share type.** `claim(&mut registry.id, CompositionKey<T>())` aborts on a
  second claim (`composition.move:77`, `recording.move:77`); independently, `share::mint`
  requires `total_supply() == 0` and consumes the only `TreasuryCap<T>` (`share.move:56-59`),
  so the registry key can never be contested. `foreign_treasury_cap_rejected`,
  `minted_currency_rejected`.
- **Type-level authorization is sound in production.** `new_internal!` is the only
  constructor of `Composition<T>`/`Recording<T>` and their caps; test-only constructors are
  stripped from published bytecode.
- **Currency immutability after `new`.** Metadata cap `Deleted` counts as claimed, so
  `update_from_legacy_metadata` aborts; `make_supply_fixed` wraps the cap in
  `SupplyState::Fixed` with no extraction path; `migrate_regulated_state_by_cap` needs a
  `DenyCapV2<T>`, which only `make_regulated` (initializer-only) or an OTW path (`T: drop`)
  can create (framework `coin_registry.move` at pin `719fb29`). `regulated_currency_rejected`,
  `unlocked_metadata_rejected`.
- **Currency registration is module-bound.** `coin_registry::new_currency<T>` on a foreign
  type fails the Sui verifier (`ESC02010`), so only the template's `initialize_currency`
  (`*_share.move:27-45`) can register a template's type, and only once (`ECurrencyAlreadyExists`).
- **Money.** Exactly `SHARE_SUPPLY = 10^14` base units are minted into the returned `Balance`
  (`composition.move:22,64-75`); no later mint, burn or rounding path exists in core.
- **ReleaseTrack proof.** `new_release_track` is the only production constructor of `ReleaseTrack`
  (`release.move:72-74`); `release_track_for_testing` is stripped from published bytecode. It takes a
  `&Recording`, and recordings are `key`-only with no deletion path, so every `ReleaseTrack` in a
  release names a recording that exists. `ReleaseTrack` has only `drop` and grants no authority;
  `new` consumes the proofs and stores `recording_ids: vector<ID>` in tracklist order.
- **Distinctness.** `release::new` sorts the u256 forms and requires strict ascending order
  (`release.move:58-60`); adjacent and non-adjacent duplicates abort with `EDuplicateRecording`.
  `ETooManyTracks` precedes it, bounding the sort at `u8::MAX` = 255 (`release.move:54-55`).
- **Abort order in `release::new`.** `ENoTracks` → `ETooManyTracks` → `EDuplicateRecording`.
  All reachable; each has a test.
- **Release IDs.** Each release gets a fresh `object::new` ID, so two releases of the same
  tracklist are distinct objects (`two_releases_of_the_same_tracks_are_distinct`). Nothing
  commits a release ID in advance.
- **Object lifecycle.** `Composition`, `Recording`, `Release` are `key`-only: no `store`, no
  `drop`, no delete function, so they can only be shared by `publish` in their creating
  transaction and never wrapped, transferred or frozen. Caps are `key, store`.
- **Derived namespaces.** Registry UIDs are never exposed. The only registry claims are the two
  work claims (`composition.move:77`, `recording.move:77`); each work and release claims its
  cap under its own UID (`composition.move:120`, `recording.move:131`, `release.move:65`).
  `derived_object::claim` marks `Claimed(id)` on the parent with a module-private key, so an
  extension holding a work's `&mut UID` cannot forge or remove the cap's claim marker, and
  its own `claim`s use different key types. Nothing can be deleted, so no re-claim after delete.
- **`uid_mut` trust.** Access requires the matching cap before and after publication
  (`post_publish_tests`); wrong `ReleaseAdminCap` aborts `EUnauthorized`
  (`release_uid_mut_wrong_cap_aborts`). Composition/recording caps cannot be mismatched in
  production (see above).
- **Events.** Each publish event carries every stored field of its object, as plain values
  (`ReleasePublishedEvent.recording_ids` mirrors `Release.recording_ids`)
  (`composition.move:44-47`, `recording.move:46-50`, `release.move:40-44`); a repeated
  publish emits again with identical fields (MP-1). The 255-track event is exercised
  (`release_published_event_at_max_tracks`).
- **README claims** about the data model, currency checks, derivation table, event fields and
  limits match the code. Two imprecisions: `initialize_currency` also takes `ctx`, and
  `composition::new` returns the supply as a `Balance` to the caller rather than "minting to"
  them (the PTB must `coin::from_balance` and transfer).

## Operational requirements

- Publish each work or release in the transaction that creates it; the objects cannot be
  held or dropped.
- Convert the returned `Balance<T>` (`coin::from_balance`) and transfer it in the same PTB.
- A release holds at most `u8::MAX` = 255 tracks, so every track position fits a `u8` and
  packages that work over a whole tracklist in one transaction stay well inside Sui's
  per-transaction limits. Without a cap the duplicate check's sort ran out of gas between
  1,000 and 2,000 tracks in tests.
- Indexers: dedupe `CompositionPublishedEvent`, `RecordingPublishedEvent` and
  `ReleasePublishedEvent` by object ID (MP-1).
- Decide and publish the `UpgradeCap` policy (burn, immutable, or governed); the registries'
  single namespaces and cap-gated `uid_mut` rest on it.

## Verification

- `sui move test --coverage`: 40/40 passed after the consent removal (49/49 at the audited
  commit); `sui move coverage summary`: 100.00 % for `composition`, `recording`, `release`.
- `sui move build -e mainnet` and `-e testnet`: OK for `miso_music`; `-e mainnet` OK for both
  templates. Toolchain `sui 1.82.1`; framework pinned at `719fb29`, share at `4cdd365`.
- Throwaway probes (not committed): repeated `publish` on shared composition and recording
  (MP-1), sibling-cap consent (test-only reachability, before the consent removal),
  foreign-module `new_currency` (rejected at build). Repeated release `publish` is a committed
  test (`release_publish_twice_emits_again`).
