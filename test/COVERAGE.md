# Additional launch tests

The existing token, supply invariant and local Uniswap v4 tests remain in place.
These additions cover:

- `TokenAdversarial.t.sol`: correctly encoded administrative calls from the
  deployer, manager, distributor and an ordinary account; allowance exhaustion
  after pool replenishment; address-specific fees and recipient exemptions;
  arbitrary wallet transfers; failed delegated buys; delegated self-transfers
  and zero transfers. Each fuzz property runs 1,000 cases.
- `AllowanceInvariant.t.sol`: 256 random sequences of 96 calls, with approvals
  and revocations separate from spending. A model tracks all five holders'
  balances and all 25 allowances, checking successful and rejected transfers,
  infinite approvals, self-transfers, dust, depletion and invalid recipients.
  Expected state comes from the call history, not reads of the token's state.
  Every sequence checks conservation and cumulative burns; each transfer also
  checks that supply cannot increase. Unexpected handler reverts fail the suite.
- `UniswapV4.t.sol`: 1,000 exact-output buy/sell round trips across both currency
  orders; exact-output sells; failed settlement rollback and successful reuse
  of the pool after the reverted unlock.

The constructor must give the deployer all `1e27` units. The 90% pool allocation
is the balance remaining after external distribution of the swarm's 10%.
Outstanding supply can only decrease, by the integer burn on PoolManager
outflows. Exact-output swap deltas describe the gross output; the recipient
receives that amount less the burn.

All tests run offline using the existing vendored v4 implementation at the
specified manager address. The pair token and unlock caller are fixtures.
Mainnet fork checks with the deployed pair token, router and launch factory
remain outside this suite; no live-state or production Merkle-distributor
verification is claimed. No dependency installation is required.
