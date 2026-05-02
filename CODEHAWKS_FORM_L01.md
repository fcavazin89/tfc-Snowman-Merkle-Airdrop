## Description
`claimSnowman` updates `s_hasClaimedSnowman` but never checks it, allowing users to claim multiple times by acquiring more tokens.

```solidity
function claimSnowman(...) external {
    // @> Missing check for s_hasClaimedSnowman[receiver]
    s_hasClaimedSnowman[receiver] = true;
}
```

## Risk
Likelihood Medium: Requires the user to acquire more tokens to satisfy the Merkle check again.
Impact High: Drains NFT supply and violates airdrop distribution rules.

## Proof of Concept
Alice successfully claims two NFTs by earning tokens between transactions, because the contract does not verify her claim status:
```solidity
function testMultipleClaims() public {
    airdrop.claimSnowman(alice, ...);
    snow.earnSnow();
    airdrop.claimSnowman(alice, ...); // Succeeds again
}
```

## Recommended Mitigation
Check the claim status mapping at the start of the function.
```diff
+ if (s_hasClaimedSnowman[receiver]) revert AlreadyClaimed();
```
