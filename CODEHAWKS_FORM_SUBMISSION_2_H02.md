## Description

**Normal behavior:**
The protocol uses EIP-712 typed data signatures to allow third parties to claim NFTs on behalf of users. The `MESSAGE_TYPEHASH` defines the structure of the message being signed, which must exactly match the data structure signed by the frontend or the user's wallet.

**Specific issue or problem:**
There is a typo in the `MESSAGE_TYPEHASH` declaration within the `SnowmanAirdrop.sol` contract. The word `address` is misspelled as `addres`.

```solidity
// src/SnowmanAirdrop.sol
    // @> Vulnerability: 'addres' is misspelled
    bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
```

Because the frontend and users will sign the correctly spelled EIP-712 struct (`address`), the generated hashes will never match the hash expected by the smart contract.

## Risk

**Likelihood:**
High
- Reason 1: The typo is hardcoded in the smart contract's constant. Every single valid signature generated externally will fail verification.
- Reason 2: The EIP-712 standard relies on exact string matching.

**Impact:**
High
- Impact 1: The entire delegated claim functionality (`claimSnowman` with signatures) is permanently broken.
- Impact 2: Users who rely on third-party claiming will be unable to receive their NFTs.

## Proof of Concept

This vulnerability can be tested by comparing the contract's typehash with the correct one:

```solidity
function testFinding2_TypehashTypo() public {
    // The typehash used in the contract
    bytes32 contractTypeHash = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
    
    // The correct typehash that the frontend/user actually signs
    bytes32 correctTypeHash = keccak256("SnowmanClaim(address receiver, uint256 amount)");
    
    // These should match for signature verification to work, but they don't!
    assertFalse(contractTypeHash == correctTypeHash);
    
    // This means ALL legitimate external signatures will fail verification.
}
```

## Recommended Mitigation

Fix the typo in the type hash to match the standard EIP-712 declaration.

```diff
// src/SnowmanAirdrop.sol

- bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
+ bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
```
