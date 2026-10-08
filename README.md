# SIMDTEST launch

`src/SIMDTESTToken.sol` contains the only launch contract, `SIMDTESTToken`.
Its constructor takes no arguments and mints **1,000,000,000 SIMDTEST with 18
decimals (1e27 minor units) to `msg.sender`**. When the launch factory deploys
it, the factory receives the entire supply. There is no later mint path,
owner, administrator, initialization call, proxy, upgrade, blacklist,
allowlist, fee exemption, or parameter setter.

The initial issuance is fixed; outstanding `totalSupply` decreases when tokens
burn and can never increase. The brief's reference to a 90% initial deployer
balance means the amount remaining **after the factory distributes 10%**.
The constructor itself always gives the deployer 100%.

## Transfers

| Source and destination | Source debit | Destination credit | Supply decrease |
| --- | --- | --- | --- |
| PoolManager to another address | `amount` | `amount - floor(amount / 100)` | `floor(amount / 100)` |
| Another address to PoolManager | `amount` | `amount` | Zero |
| Wallet to wallet | `amount` | `amount` | Zero |

The fixed PoolManager is
`0x000000000004444c5dc75cB358380D2e3dE08A90` on Ethereum mainnet (chain ID 1).
The rule tests `from`, including with `transferFrom`; the spender has no
effect on the fee. Allowances are spent on the gross amount, with maximum
`uint256` treated as unlimited. A failed operation reverts all changes.
`approve` replaces the allowance and emits `Approval`; spending allowance
does not emit another `Approval` event.

Burns reduce supply directly and emit `Transfer(from, address(0), burned)`;
the zero address does not acquire a balance. Delivery emits a separate
`Transfer` for the net amount. Integer rounding leaves less than one minor
unit of theoretical fee unburned per transfer. Transfers below 100 minor
units burn zero. Zero-value transfers are allowed, but transfers to or from
the zero address and approvals to the zero address revert.

Ordinary self-transfers preserve the balance. A PoolManager self-transfer
still burns 1%, reducing its balance only by that burn. There are no recipient
exemptions, including the deployer or distributor.

The token does not inspect swaps: **every outgoing PoolManager transfer is
subject to the burn**, including liquidity withdrawals or other payouts.
Incoming seeding and sell payments arrive whole. Integrators must use actual
recipient balance changes for buy output and slippage checks; a gross v4
output delta is larger than the recipient's net delivery. Splitting tiny
transfers can reduce rounding fees. These follow from the requested source
address rule and integer token units.

## Launch manifest and responsibilities

`launch.json` has kind `custom_token`, contract name `SIMDTESTToken` (a plain
name fitting bytes32), empty constructor arguments, and no application
contracts. Chain ID is documented here and in notes, not as a manifest key.

| Parameter | Exact value |
| --- | --- |
| Paired currency (IMD) | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee | `3000` |
| Tick spacing | `60` |
| Provenance sqrtPriceX96 | `125270724187523965593206900` |
| `economics.poolBps` | `9000` |
| `economics.initialMarketCapWei` | `2500000000000000000000` (2500 IMD, in paired-currency minor units) |
| `economics.remainderTo` | `0x000000000000000000000000000000000000dead` |

The addresses and economics come from the assignment. The remainder address
is the explicitly requested destination. No requester input is missing.
The initial price is provenance with SIMDTEST as currency0; the launch
deployer derives the actual opening price from the economics and deployed
currency order.

The existing launch factory is responsible for deploying the token, sending
100,000,000 tokens to its Merkle distributor, using the 900,000,000-token
pool allocation for single-sided v4 liquidity, and forwarding any unused
remainder to `remainderTo`. The distributor handles claims. The token neither
reserves balances nor sends the swarm allocation itself. There are no
post-launch settings or administrative transactions for the token.

The launch operator must use Ethereum mainnet, derive the sorted pool key,
opening price, ticks and liquidity through the launch system, and verify the
deployed bytecode and full factory balance before distribution. The contract
does not enforce chain ID. No deployment, transaction broadcast, wallet key
access, or live-chain configuration is included in this project.

## Build and checks

With Foundry and solc 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
python3 tools/check_manifest.py
```

`foundry.toml` pins solc 0.8.26, Cancun, optimizer enabled with 200 runs, and
`bytecode_hash = "none"`. It enables neither FFI nor filesystem permissions.
The token has no dependencies. All integration-test dependencies are ordinary
vendored files with pinned revisions and licenses in `DEPENDENCIES.md`.
The tests need no network, environment variables, external test files, or
dependency installation. Test accounts and the paired-token mock are fixtures,
not deployment configuration.

The suite covers full issuance to an actual contract deployer, factory/swarm
flows, direct and delegated burns, untaxed sells, rounding, self-transfers,
allowances, event values, rejected admin selectors, opcode restrictions,
failure rollback, 1,000 cases for each fuzz property, and supply/balance
conservation across 256 invariant sequences of 64 calls.

The integration suite executes the pinned **real v4 PoolManager source** at
the requested address locally. It seeds nearly the full 90% allocation with
single-sided liquidity and buys/sells in both token orders. It also confirms
that underpayment reverts the entire unlock, including any earlier burn.
The pair token and unlock caller are test fixtures; the production factory,
initialization guard, Merkle proof verification and router behavior are not
reimplemented or certified here. Mainnet fork checks with the actual paired
token and production router/factory remain an operator validation step.
This suite is not an independent security audit; no Slither or Mythril run
is claimed.

