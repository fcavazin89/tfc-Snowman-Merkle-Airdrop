# Description
The `SnowmanAirdrop` contract allows users to claim NFTs by providing a cryptographic signature. During this process, the contract must verify that the user intended to claim a specific amount of tokens. 

The current implementation of `getMessageHash()` and `claimSnowman()` does not take the intended claim amount as a parameter. Instead, it dynamically queries the user's current token balance using `i_snow.balanceOf(receiver)`.

```solidity
// src/SnowmanAirdrop.sol

  function getMessageHash(address receiver) public view returns (bytes32) {
    // ...
    // @> Vulnerability: Reads current balance instead of using a fixed signed amount.
    uint256 amount = i_snow.balanceOf(receiver);

    return _hashTypedDataV4(
        keccak256(abi.encode(MESSAGE_TYPEHASH, SnowmanClaim({receiver: receiver, amount: amount})))
    );
  }
```

This creates a front-running opportunity. An attacker can monitor the mempool for a pending `claimSnowman` transaction. Before that transaction is mined, the attacker can transfer a minimal amount of Snow tokens (e.g., 1 wei) to the receiver. This changes the receiver's balance, which in turn changes the hash calculated by the contract, causing the user's signature to become invalid and the transaction to revert.

# Risk
## Likelihood: Medium
An attacker can easily automate this process by monitoring the mempool. The cost of the attack is extremely low (1 wei of Snow token + gas), making it a cheap and effective way to harass users or block claims.

## Impact: High
A malicious actor can permanently prevent any user from claiming their NFTs via the signature mechanism. By repeatedly altering the user's balance, the attacker ensures that the user's signed message never matches the contract's calculated hash, resulting in a permanent Denial-of-Service (DoS).

# Proof of Concept
The following PoC demonstrates the attack. Alice signs a message for her balance of 1 Snow token. Bob (the attacker) detects her transaction and sends her 1 additional token. When Alice's claim transaction executes, it reverts because the contract now sees a balance of 2 tokens, which does not match her signature for 1 token.

```solidity
function testFinding3_DoSClaimSnowman() public {
    // Alice has 1 token and signs a valid message
    assert(snow.balanceOf(alice) == 1);
    bytes32 alDigest = airdrop.getMessageHash(alice);
    (uint8 alV, bytes32 alR, bytes32 alS) = vm.sign(alKey, alDigest);

    // Bob front-runs Alice's claim by sending her 1 token
    vm.prank(bob);
    snow.transfer(alice, 1);

    // Alice's transaction now reverts due to the balance change
    vm.prank(satoshi);
    vm.expectRevert(); 
    airdrop.claimSnowman(alice, AL_PROOF, alV, alR, alS);
}
```

# Recommended Mitigation
Modify the signature verification logic to include the intended claim `amount` as an explicit parameter in both `getMessageHash` and `claimSnowman`. This ensures the signature is verified against a fixed value that cannot be manipulated by third-party balance changes.

```solidity
function claimSnowman(
    address receiver, 
    uint256 amount, // New parameter
    bytes32[] calldata merkleProof, 
    uint8 v, 
    bytes32 r, 
    bytes32 s
) external nonReentrant {
    // Verify signature using the passed amount
    if (!_isValidSignature(receiver, getMessageHash(receiver, amount), v, r, s)) {
        revert SA__InvalidSignature();
    }
    // ...
}
```
