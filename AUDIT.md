# Security Audit — `music-protocol`

Audited at `1538d77035c4fb6b45b74f7d85168b7c3a80564b` (2026-10-21). Covers the `miso_music`
package (`composition`, `recording`, `release`), the share templates
`templates/composition_share` and `templates/recording_share`, and the pinned dependency
`share::share::mint` (misofm/share `4cdd365`) that core's currency checks rely on. Later commits
only inline `assert_distinct` into `release::new`, rename and reorder getters, and add method
aliases. Later commits only apply naming and ordering standards; line references are to
the current code.

## What it does

Identity and release-consent core: one `Composition<CompositionShare>` and one
`Recording<RecordingShare>` per share coin type, each backed by a fixed 100M-share currency,
and `Release` objects whose IDs commit to an ordered tracklist plus a salt and which can only
be created from recording-admin consents. See [README](README.md).

## Trust model

- **Anyone** may publish a share template, register its currency, create a composition or
  recording (`composition::new`, `recording::new`), consent-collect and create a release
  (`release::new`), and read every object (`uid`, `derive_address`, getters).
- **Share package publisher** holds `InitializeCurrencyTicket` (`key, store`, transferable);
  it is the only path to `coin_registry::new_currency<T>` for that type because the Sui
  verifier rejects `new_currency` on a type from another module (checked: a probe calling it
  with a foreign type fails to build with `ESC02010`).
- **`TreasuryCap<T>` holder** is the only party who can create the work for `T`;
  `share::mint` consumes the cap and fixes supply, so there is at most one work per type and
  no later minting (`share.move:31-61`).
- **`CompositionAdminCap<T>` / `RecordingAdminCap<T>` holder** (bearer, `key, store`): can
  publish the work, obtain `&mut UID` at any time (`composition.move:106-111`,
  `recording.move:113-118`) and, for recordings, issue `ReleaseConsent`
  (`release.move:156-162`). Authorization is by type parameter: exactly one work and one cap
  exist per `T`, both derived (`composition.move:76-78,115-123`, `recording.move:76-79,122-134`).
- **`ReleaseAdminCap` holder** (bearer, `key, store`): can publish the release and obtain
  `&mut UID`; checked by stored `release_id` (`release.move:188-190,192-195`).
- **Package upgrader** (holder of the `UpgradeCap`): can add functions that claim new keys
  under the three registries or expose `&mut UID` without a cap. Core has no on-chain
  defence against this; see Operational requirements.
- **Nobody** can: construct a registry after `init` (`composition.move:51-53`,
  `recording.move:54-56`, `release.move:81-83`); mutate a registry UID; change
  `Recording.composition_id` or `Release.recording_ids`; unpack a `ReleaseConsent` outside
  `release::new`; mint shares after creation; re-regulate or edit the currency metadata
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
`Release` is not affected (`ENotInitializedState`, `release.move:184`).

**MP-2 · Info · Accepted** — Consents do not bind a creator. `release::new` is permissionless
(`release.move:85-118`): whoever assembles every `ReleaseConsent` for a release ID in one
transaction receives the `ReleaseAdminCap`. Bare consents cannot leave the transaction
(`ReleaseConsent` has no `key`), so this only matters for extensions that wrap them;
creator binding and escrow belong to extensions.

**MP-3 · Info · Accepted** — Core verifies the currency, not the template bytecode.
`share::is_type` matches only `<any address>::composition_share::CompositionShare` /
`::recording_share::RecordingShare` (`share.move:65-73`); a hand-written package with that
module and struct name passes (the test fixture `miso_music::composition_share` does). All
core guarantees (locked metadata, unregulated, exact metadata, zero prior supply, matching
treasury cap, fixed supply) are checked on `Currency<T>` and the consumed `TreasuryCap<T>`,
so they hold regardless of the bytecode. The README's "publish the template unchanged" is
tooling guidance, not an on-chain property.

**MP-4 · Info · Open** — `ReleaseAdminCap.release_id` is stored although the cap ID is derived
from the release (`release.move:37-40,113-116`). `authorize` could compare
`derived_object::derive_address(object::id(release), ReleaseAdminCapKey())` with the cap ID
instead. Storage-only; no security impact.

**MP-5 · Info · Open** — Single-transaction consent collection is bounded by transaction
limits, not by `MAX_TRACKS`. A 1,000-track release collected in one PTB needs ~1,000
`consent` calls plus `new` and `publish` (under the 1,024-command limit) but ~2,001 object
inputs (1,000 shared recordings, 1,000 caps, the registry) and a transaction near the 128 KiB
size limit. Releases near the cap must gather consents over several transactions through a
wrapping extension.

**MP-6 · Info · Open** — All creations serialize on one shared registry per kind
(`composition.move:56`, `recording.move:59`, `release.move:86`). Throughput of
`composition::new`, `recording::new` and `release::new` is bounded by consensus sequencing
of that object. `derive_address` reads only.

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
  stripped from published bytecode. A probe confirmed `release::consent` accepts a sibling
  cap of the same type, which is reachable only through `new_for_testing`.
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
- **Release ID commitment.** `release_digest` hashes `bcs(vector<ID>) ‖ bcs(salt)` with the
  salt length fixed at 32 (`release.move:199-204`); both prefixes are ULEB lengths so the
  encoding is injective. Reference digests and salt-length aborts are tested
  (`release_digest_tests`). Every consent's `release_id` must equal the claimed derived ID
  (`release.move:109-111`), binding membership and order.
- **Consent single use.** A derived release ID is claimable once (`duplicate_digest_aborts`),
  `ReleaseConsent` has no `copy`, and only `release::new` unpacks it, so a consent cannot be
  replayed into a second release.
- **Distinctness.** `release::new` sorts the u256 forms and requires strict ascending order
  (`release.move:99-101`); adjacent and non-adjacent duplicates abort with `EDuplicateRecording`.
  `ETooManyTracks` precedes it, bounding the sort at 1,000 (`release.move:90-91`).
- **Abort order in `release::new`.** `ENoTracks` → `ETooManyTracks` → `EDuplicateRecording`
  → `EInvalidSaltLength` → `derived_object::EObjectAlreadyExists` → `EUnauthorizedAssignment`.
  All reachable; each has a test.
- **Object lifecycle.** `Composition`, `Recording`, `Release` are `key`-only: no `store`, no
  `drop`, no delete function, so they can only be shared by `publish` in their creating
  transaction and never wrapped, transferred or frozen. Caps are `key, store`.
- **Derived namespaces.** Registry UIDs are never exposed; only the three `claim` sites exist.
  `derived_object::claim` marks `Claimed(id)` on the parent with a module-private key, so an
  extension holding a work's `&mut UID` cannot forge or remove the cap's claim marker, and
  its own `claim`s use different key types. Nothing can be deleted, so no re-claim after delete.
- **`uid_mut` trust.** Access requires the matching cap before and after publication
  (`post_publish_tests`); wrong `ReleaseAdminCap` aborts `EUnauthorized`
  (`release_uid_mut_wrong_cap_aborts`). Composition/recording caps cannot be mismatched in
  production (see above).
- **Events.** Each publish event carries every stored field of its object
  (`composition.move:44-47`, `recording.move:46-50`, `release.move:66-71`); `Release` emits
  after the state flips to `Published`, so a second publish aborts before emitting. The
  1,000-track event is exercised (`release_published_event_at_max_tracks`).
- **README claims** about the data model, currency checks, derivation table, event fields and
  limits match the code. Two imprecisions: `initialize_currency` also takes `ctx`, and
  `composition::new` returns the supply as a `Balance` to the caller rather than "minting to"
  them (the PTB must `coin::from_balance` and transfer).

## Operational requirements

- Publish each work or release in the transaction that creates it; the objects cannot be
  held or dropped.
- Convert the returned `Balance<T>` (`coin::from_balance`) and transfer it in the same PTB.
- Generate the salt as 32 random bytes and share it only with the consenting recording admins;
  it becomes public in `ReleasePublishedEvent`.
- Collect consents in one PTB or through an extension that wraps `ReleaseConsent`; near 1,000
  tracks the single-PTB route exceeds transaction limits (MP-5).
- Indexers: dedupe `CompositionPublishedEvent` / `RecordingPublishedEvent` by object ID (MP-1).
- Decide and publish the `UpgradeCap` policy (burn, immutable, or governed); the registries'
  single namespaces and cap-gated `uid_mut` rest on it.

## Verification

- `sui move test --coverage`: 49/49 passed; `sui move coverage summary`: 100.00 % for
  `composition`, `recording`, `release`.
- `sui move build -e mainnet` and `-e testnet`: OK for `miso_music`; `-e mainnet` OK for both
  templates. Toolchain `sui 1.82.1`; framework pinned at `719fb29`, share at `4cdd365`.
- Throwaway probes (not committed): repeated `publish` on shared composition and recording
  (MP-1), sibling-cap consent (test-only reachability), foreign-module `new_currency`
  (rejected at build).
