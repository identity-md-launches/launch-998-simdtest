# Vendored test dependencies

The production token is self-contained. The following unchanged upstream files
are used only by `test/UniswapV4.t.sol`; all transitive imports needed to compile
`PoolManager.sol` are included. No Git submodules or package installers are used.

| Directory | Upstream | Pinned revision | License |
| --- | --- | --- | --- |
| `lib/v4-core` | [Uniswap/v4-core](https://github.com/Uniswap/v4-core/tree/46c6834698c48bc4a463a86d8420f4eb1d7f3b75) | `46c6834698c48bc4a463a86d8420f4eb1d7f3b75` | Per-file SPDX: BUSL-1.1 or MIT; texts in `lib/v4-core/licenses/` |
| `lib/solmate` | [transmissions11/solmate](https://github.com/transmissions11/solmate/tree/4b47a19038b798b4a33d9749d25e570443520647) | `4b47a19038b798b4a33d9749d25e570443520647` (v4-core's pinned dependency) | AGPL-3.0-only on `Owned.sol`; upstream license in `lib/solmate/LICENSE` |

`lib/SHA256SUMS` records the exact downloaded file contents. The v4 test fixture
has the upstream PoolManager's own protocol administration; those powers are
not inherited by or included in `SIMDTESTToken`. The locally compiled manager
is a test deployment, not an assertion of byte-for-byte mainnet equivalence.

