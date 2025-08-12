# Uniswap v4 Hook Template

### Requirements
To set up the project, run the following commands in your terminal to install dependencies and run the tests:

```
forge install
forge test
```

### Tests

## testSwappingUsingHooks
To visualize the exact swapFee that is charged during the swap, run the test `testSwappingUsingHooks` w/ the next command:
`forge test --match-test testSwappingUsingHooks -vvvv | grep -i "emit Swap"`
- Demonstrates how `beforeSwap()` hook is capable of overriding the LP_FEES to charge during the swap, as well as how `afterSwap()` is able to charge extra fees by calling `PoolManager.take()` and having those assets be paid out by the original swapper and received on the Hook contract.
   - This achieves not charging fees during the swap and only charing the taken fees on the `afterSwap()`