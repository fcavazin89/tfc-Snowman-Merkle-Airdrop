## Description
`getMessageHash` uses dynamic `balanceOf(receiver)`. An attacker can front-run a claim by sending 1 wei to the user, invalidating their signature.

```solidity
function getMessageHash(address receiver) public view returns (bytes32) {
    uint256 amount = i_snow.balanceOf(receiver); // @> Manipulatable via front-running
    return _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, SnowmanClaim({receiver: receiver, amount: amount}))));
}
```

## Risk
Likelihood Medium: Minimal cost (1 wei) to execute a front-running attack in the mempool.
Impact High: Permanent Denial-of-Service for targeted users attempting to claim via signature.

## Proof of Concept
Attacker sends 1 wei to Alice after she signs, altering her balance and causing her claim transaction to revert:
```solidity
function testDoS() public {
    bytes32 digest = airdrop.getMessageHash(alice);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(alKey, digest);
    vm.prank(bob); snow.transfer(alice, 1); // Front-run
    vm.expectRevert(); airdrop.claimSnowman(alice, proof, v, r, s);
}
```

## Recommended Mitigation
Pass `amount` as a parameter to ensure signatures are verified against a fixed value.
```solidity
function claimSnowman(address receiver, uint256 amount, ...) external { ... }
```
