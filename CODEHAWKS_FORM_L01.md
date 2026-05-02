# Description
The `SnowmanAirdrop` contract is designed to distribute NFTs to eligible users. To ensure a fair distribution, airdrop mechanisms typically include a check to prevent the same address from claiming rewards multiple times.

In the `claimSnowman` function, the contract correctly updates the `s_hasClaimedSnowman` mapping to `true` after a successful claim. However, the function fails to validate this state at the beginning of the execution.

```solidity
// src/SnowmanAirdrop.sol

    function claimSnowman(address receiver, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
    {
        // @> Vulnerability: There is no check here to see if s_hasClaimedSnowman[receiver] is already true.
        if (receiver == address(0)) {
            revert SA__ZeroAddress();
        }
        // ... (claim logic)
        s_hasClaimedSnowman[receiver] = true;
    }
```

This oversight allows an eligible user to claim an NFT, acquire more Snow tokens (e.g., via the `earnSnow` or `buySnow` functions), and then successfully call `claimSnowman` again. As long as they have a valid Merkle proof for their new balance, the contract will process the second claim.

# Risk
## Likelihood: Medium
While it requires the user to acquire additional tokens between claims, this is easily achievable through the protocol's own mechanisms. Users motivated by profit can exploit this to accumulate a disproportionate share of the airdrop.

## Impact: High
The vulnerability allows for the unauthorized drainage of the NFT collection. It breaks the "one claim per user" economic model of the airdrop and results in an unfair distribution of assets.

# Proof of Concept
The following test demonstrates how Alice can bypass the claim limit. She claims her first NFT, waits a week to earn more Snow tokens, and then successfully claims a second NFT because the contract never checks if she has already participated.

```solidity
function testMultipleClaimsAllowed() public {
    // Alice performs her first legitimate claim
    vm.prank(alice);
    airdrop.claimSnowman(alice, AL_PROOF, v, r, s);
    assert(nft.balanceOf(alice) == 1);

    // Alice acquires more tokens via the protocol's earn mechanic
    vm.warp(block.timestamp + 1 weeks);
    vm.prank(alice);
    snow.earnSnow();

    // Alice successfully claims a SECOND NFT because her status isn't checked
    vm.prank(alice);
    airdrop.claimSnowman(alice, AL_PROOF, v2, r2, s2);
    assert(nft.balanceOf(alice) == 2);
}
```

# Recommended Mitigation
Add a conditional check at the start of the `claimSnowman` function to revert the transaction if the recipient has already claimed their NFT.

```diff
// src/SnowmanAirdrop.sol

+ error SA__AlreadyClaimed();

  function claimSnowman(...) external nonReentrant {
+     if (s_hasClaimedSnowman[receiver]) {
+         revert SA__AlreadyClaimed();
+     }
      // ...
  }
```
