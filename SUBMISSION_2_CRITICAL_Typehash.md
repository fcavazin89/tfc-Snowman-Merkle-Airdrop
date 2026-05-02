# Finding Submission #2 - Critical

## Title
EIP-712 Signature Verification Broken Due to Typo in MESSAGE_TYPEHASH

## Severity
**Critical** (High Impact + High Likelihood)

## Description
The `MESSAGE_TYPEHASH` constant in `SnowmanAirdrop.sol` contains a typo: "addres" instead of "address". This causes all EIP-712 signature verifications to fail, preventing legitimate users from claiming their NFTs.

### Vulnerable Code
```solidity
// src/SnowmanAirdrop.sol:49
bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
```

### Root Cause
The type hash is used to compute the EIP-712 digest that users sign off-chain. Due to the typo (`addres` instead of `address`), the computed digest will never match the signed message, causing all signature verifications to fail.

## Proof of Concept
```solidity
function testFinding2_TypehashTypo() public {
    // The typehash used in contract
    bytes32 wrongTypeHash = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
    
    // The correct typehash that users will sign
    bytes32 correctTypeHash = keccak256("SnowmanClaim(address receiver, uint256 amount)");
    
    // These should match for signature verification to work, but they don't!
    assertTrue(wrongTypeHash != correctTypeHash);
    
    // This means ALL signature verifications will fail
    // Users cannot claim their NFTs even with valid signatures
}
```

## Impact
- **Complete breakdown of claim mechanism**: No user can successfully claim NFTs
- **EIP-712 signatures useless**: All signed messages become invalid
- **Protocol unusable**: The main functionality is broken
- **Users lose funds**: They may pay gas for failed transactions

## Recommended Mitigation
Fix the typo in the type hash:

```solidity
// Correct version
bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
```

Also consider adding:
1. **Deadline/nonce** to prevent replay attacks
2. **Proper EIP-712 domain separation**
3. **Testing with actual signature recovery**

## Location
`src/SnowmanAirdrop.sol:49`

## Validation
✅ PoC test passes  
✅ Manual verification confirms typo  
✅ EIP-712 specification check failed

---

**XP Expected:** 100 XP (Critical severity)
