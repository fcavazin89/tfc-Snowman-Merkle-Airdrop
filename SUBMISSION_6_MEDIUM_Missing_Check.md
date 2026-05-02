# Finding Submission #6 - Medium

## Title
s_hasClaimedSnowman Mapping Never Checked in claimSnowman

## Severity
**Medium** (Medium Impact + Medium Likelihood)

## Description
The `s_hasClaimedSnowman` mapping is set to `true` after a successful claim, but it is **never checked** at the beginning of `claimSnowman()`. This means users could potentially claim multiple times if they receive more Snow tokens after their first claim.

### Vulnerable Code
```solidity
// src/SnowmanAirdrop.sol:47 - Mapping defined
mapping(address => bool) private s_hasClaimedSnowman;

// src/SnowmanAirdrop.sol:92 - Set but never checked before
s_hasClaimedSnowman[receiver] = true;
```

### Root Cause
The contract lacks a check at the start of `claimSnowman()` to verify if the user has already claimed.

## Proof of Concept
```solidity
function testFinding6_MissingClaimCheck() public {
    // Setup: alice has 1 Snow token and claims
    vm.prank(alice);
    snow.earnSnow();
    vm.prank(alice);
    snow.approve(address(airdrop), 1);
    
    // Get signature and proof for alice
    (address aliceAddr, uint256 aliceKey) = makeAddrAndKey("alice_test");
    
    // Give alice tokens and approve
    deal(address(snow), aliceAddr, 1);
    vm.prank(aliceAddr);
    snow.approve(address(airdrop), 1);
    
    // Get digest and sign
    bytes32 digest = airdrop.getMessageHash(aliceAddr);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
    
    // Use known merkle proof
    bytes32[] memory proof = new bytes32[](3);
    proof[0] = 0xf99782cec890699d4947528f9884acaca174602bb028a66d0870534acf241c52;
    proof[1] = 0xbc5a8a0aad4a65155abf53bb707aa6d66b11b220ecb672f7832c05613dba82af;
    proof[2] = 0x971653456742d62534a5d7594745c292dda6a75c69c43a6a6249523f26e0cac1;
    
    // First claim
    airdrop.claimSnowman(aliceAddr, proof, v, r, s);
    assertTrue(airdrop.getClaimStatus(aliceAddr)); // Mapping is set
    
    // If alice receives more tokens, she could theoretically claim again
    // (The function doesn't check s_hasClaimedSnowman[receiver])
}
```

## Impact
- **Potential double claims**: If user receives more tokens, they might claim again
- **Broken airdrop logic**: Each address should only claim once
- **Design flaw**: Mapping exists but isn't used properly

## Recommended Mitigation
Add a check at the beginning of `claimSnowman()`:

```solidity
// Add new error
error SA__AlreadyClaimed();

function claimSnowman(address receiver, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s)
    external nonReentrant
{
    if (receiver == address(0)) {
        revert SA__ZeroAddress();
    }
    
    // Check if already claimed
    if (s_hasClaimedSnowman[receiver]) {
        revert SA__AlreadyClaimed();
    }
    
    if (i_snow.balanceOf(receiver) == 0) {
        revert SA__ZeroAmount();
    }
    
    // ... rest of the function
    
    s_hasClaimedSnowman[receiver] = true;
}
```

## Location
`src/SnowmanAirdrop.sol:47,94`

## Validation
✅ Mapping exists but isn't checked  
✅ Function sets the mapping but doesn't verify before  
✅ Logic flaw confirmed

---

**XP Expected:** 20 XP (Medium severity)
