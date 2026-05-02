## Description
`MESSAGE_TYPEHASH` misspells `address` as `addres`, causing all standard frontend signatures to fail verification.

```solidity
// @> typo 'addres'
bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
```

## Risk
Likelihood High: The typo is hardcoded; all standard frontend signatures will fail verification.
Impact High: Signature-based claims are completely broken.

## Proof of Concept
The contract's hash differs from the standard EIP-712 format used by wallets, failing the ecrecover check:
```solidity
function testTypo() public {
    bytes32 CORRECT = keccak256("SnowmanClaim(address receiver, uint256 amount)");
    assertFalse(CORRECT == airdrop.getMessageHash(alice));
}
```

## Recommended Mitigation
Fix the spelling of `address` in the type hash constant.
```diff
- keccak256("SnowmanClaim(addres receiver, uint256 amount)");
+ keccak256("SnowmanClaim(address receiver, uint256 amount)");
```
