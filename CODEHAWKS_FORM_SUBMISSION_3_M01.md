## Description

**Normal behavior:**
To claim a Snowman NFT using a signature, a user signs a message containing their address and their claimable amount. The contract should verify this specific signature against the user's intended claim amount.

**Specific issue or problem:**
In `SnowmanAirdrop.sol`, the functions `getMessageHash()` and `claimSnowman()` do not accept `amount` as an argument. Instead, they dynamically read the user's current token balance using `i_snow.balanceOf(receiver)`.

```solidity
// src/SnowmanAirdrop.sol
    function claimSnowman(address receiver, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
        // ...
        // @> Vulnerability: Reads current balance instead of using a fixed signed amount
        uint256 amount = i_snow.balanceOf(receiver);
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(receiver, amount))));
        // ...
    }
```

This allows a griefing/DoS attack. An attacker can front-run a user's claim transaction by transferring a tiny amount of Snow tokens (e.g., 1 wei) to the user. This changes the user's `balanceOf`, causing the contract to calculate a different hash, which invalidates the user's previously signed message and reverts the transaction.

## Risk

**Likelihood:**
Medium
- Reason 1: The attacker needs to monitor the mempool and execute a front-running transaction.
- Reason 2: The cost of the attack is minimal (1 wei of Snow token + gas fees), making it easy to execute repeatedly.

**Impact:**
High
- Impact 1: A malicious actor can permanently lock out users from claiming their NFTs by continuously front-running their claim transactions.
- Impact 2: Breaks the core airdrop functionality for targeted users.

## Proof of Concept

An attacker can force a claim transaction to revert by altering the victim's balance:

```solidity
function testFinding3_DoSClaimSnowman() public {
    // 1. User has 1 Snow token and generates a valid signature
    assert(snow.balanceOf(user) == 1);
    bytes32 userDigest = airdrop.getMessageHash(user);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, userDigest);

    // 2. Attacker front-runs the claim transaction
    vm.prank(attacker);
    snow.transfer(user, 1); // Attacker sends 1 wei of Snow to the user

    // 3. User's balance has changed
    assert(snow.balanceOf(user) == 2);

    // 4. The legitimate claim transaction now reverts because the signature 
    // was for amount=1, but the contract now reads amount=2
    vm.prank(relayer);
    vm.expectRevert(); // Fails with SA__InvalidSignature
    airdrop.claimSnowman(user, proof, v, r, s);
}
```

## Recommended Mitigation

Pass the `amount` as a parameter to both `getMessageHash` and `claimSnowman` so that the signature is verified against a specific, immutable value rather than a dynamic balance.

```diff
// src/SnowmanAirdrop.sol

- function claimSnowman(address receiver, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
+ function claimSnowman(address receiver, uint256 amount, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
      if (receiver == address(0)) revert SA__ZeroAddress();
-     if (i_snow.balanceOf(receiver) == 0) revert SA__ZeroAmount();

-     if (!_isValidSignature(receiver, getMessageHash(receiver), v, r, s)) revert SA__InvalidSignature();
+     if (!_isValidSignature(receiver, getMessageHash(receiver, amount), v, r, s)) revert SA__InvalidSignature();

-     uint256 amount = i_snow.balanceOf(receiver);

      bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(receiver, amount))));
      // ...
  }
  
- function getMessageHash(address receiver) public view returns (bytes32) {
+ function getMessageHash(address receiver, uint256 amount) public view returns (bytes32) {
-     if (i_snow.balanceOf(receiver) == 0) revert SA__ZeroAmount();
-     uint256 amount = i_snow.balanceOf(receiver);
      
      return _hashTypedDataV4(
          keccak256(abi.encode(MESSAGE_TYPEHASH, SnowmanClaim({receiver: receiver, amount: amount})))
      );
  }
```
