# Miso Music Protocol

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Shared on-chain compositions, recordings and releases for Sui, published as the
`miso_music` Move package.

**Documentation:** [docs.miso.fm/protocol](https://docs.miso.fm/protocol/overview/)

## Use

```toml
[dependencies]
miso_music = { git = "https://github.com/misofm/music-protocol.git", rev = "<commit>" }
```

Pin a full commit hash. The package is not yet published to a network, so there are
no package or registry IDs to depend on.

## Repository

| Path | Contents |
|---|---|
| `sources/` | The `composition`, `recording` and `release` modules |
| `templates/` | The `composition_share` and `recording_share` coin templates; each work publishes an unchanged copy |
| `tests/` | Unit and end-to-end tests, with the templates as test-only dependencies |

The one Move dependency is [share](https://github.com/misofm/share), pinned in
`Move.toml`. Sui framework versions are pinned in `Move.lock`.

## Build and test

```sh
sui move build
sui move test
```

## Security

See [AUDIT.md](AUDIT.md).

## License

[Apache 2.0](LICENSE) © Miso Labs, Inc.
