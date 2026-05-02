# ============================================================
# SUBMISSION 1 of 5 — [H-01] Unrestricted NFT Minting
# ============================================================
# Title: Anyone Can Mint Unlimited Snowman NFTs Without Staking
# Impact: High
# Likelihood: High
# Scope: src/Snowman.sol
# ============================================================

# Description
The `Snowman` contract implements a `mintSnowman` function intended to be called exclusively by the `SnowmanAirdrop` contract after verifying Merkle proofs, EIP-712 signatures, and Snow token staking. However, the function lacks any access control.

Any address on the network can call `mintSnowman()` directly and mint an arbitrary number of NFTs to any recipient, completely bypassing the staking requirement and the Merkle-based distribution logic.

```solidity
// src/Snowman.sol

    // @> Vulnerability: External function with no access control modifier
    function mintSnowman(address receiver, uint256 amount) external {
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(receiver, s_TokenCounter);
            emit SnowmanMinted(receiver, s_TokenCounter);
            s_TokenCounter++;
        }
    }
```

# Risk
## Likelihood: High
The function is publicly accessible and requires no special permissions, tokens, or expensive prerequisites. Any user can trigger the minting at any time.

## Impact: High
An attacker can mint the entire NFT supply for free, destroying the rarity and economic value of the collection and rendering the protocol's staking and airdrop mechanism obsolete.

# Proof of Concept
The following test demonstrates that an attacker can mint 100 NFTs for free by calling `mintSnowman` directly, without providing any Snow tokens or Merkle proofs:

```solidity
function testFinding1_UnrestrictedMinting() public {
    address attacker = makeAddr("attacker");
    uint256 initialCounter = nft.getTokenCounter();
    
    vm.prank(attacker);
    nft.mintSnowman(attacker, 100);
    
    assert(nft.balanceOf(attacker) == 100);
    assert(nft.getTokenCounter() == initialCounter + 100);
}
```

# Recommended Mitigation
Add an `onlyAirdrop` modifier to restrict `mintSnowman` to the authorized airdrop contract. The airdrop address should be set in the constructor or via a protected setter.

```diff
// src/Snowman.sol

+ address public s_airdropContract;
+ error SM__NotAllowed();
+ 
+ modifier onlyAirdrop() {
+     if (msg.sender != s_airdropContract) revert SM__NotAllowed();
+     _;
+ }

- function mintSnowman(address receiver, uint256 amount) external {
+ function mintSnowman(address receiver, uint256 amount) external onlyAirdrop {
      for (uint256 i = 0; i < amount; i++) {
          _safeMint(receiver, s_TokenCounter);
          emit SnowmanMinted(receiver, s_TokenCounter);
          s_TokenCounter++;
      }
  }

+ function setAirdropContract(address _airdrop) external onlyOwner {
+     s_airdropContract = _airdrop;
+ }
```


# ============================================================
# SUBMISSION 2 of 5 — [H-02] EIP-712 Typehash Typo
# ============================================================
# Title: Unconsistent MESSAGE_TYPEHASH with EIP-712 declaration on SnowmanAirdrop
# Impact: High
# Likelihood: High
# Scope: src/SnowmanAirdrop.sol
# ============================================================

# Description
The `SnowmanAirdrop` contract uses EIP-712 typed data signatures to verify that a claim is authorized by the recipient. This depends on a constant `MESSAGE_TYPEHASH` that must exactly match the string used by the frontend when generating signatures.

There is a typo in the declaration: `address` is misspelled as `addres` (missing the final "s"). Because off-chain libraries (Ethers.js, Viem) always use the correct spelling, the cryptographic digest calculated by the contract will never match the digest signed by the user.

```solidity
// src/SnowmanAirdrop.sol

    // @> Vulnerability: Typo — 'addres' instead of 'address'
    bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
```

# Risk
## Likelihood: High
The typo is hardcoded in a `private constant`. EIP-712 requires an exact character-for-character match, so every legitimate signature will fail verification.

## Impact: High
The signature verification mechanism is completely broken. No user can successfully use the delegated claim functionality, which is a core feature of the airdrop protocol.

# Proof of Concept
The following test compares the contract's incorrect typehash with the standard-compliant typehash that a frontend would use. They do not match, leading to permanent signature validation failure:

```solidity
function testFinding2_TypehashTypo() public {
    bytes32 CORRECT_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
    bytes32 contractDigest = airdrop.getMessageHash(alice);
    
    assertFalse(
        CORRECT_TYPEHASH == contractDigest,
        "Mismatch between standard and contract typehash"
    );
}
```

# Recommended Mitigation
Correct the spelling of `address` in the `MESSAGE_TYPEHASH` constant.

```diff
// src/SnowmanAirdrop.sol

- bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
+ bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
```


# ============================================================
# SUBMISSION 3 of 5 — [M-01] DoS via Balance Manipulation
# ============================================================
# Title: DoS to a user trying to claim a Snowman via balance manipulation
# Impact: High
# Likelihood: Medium
# Scope: src/SnowmanAirdrop.sol
# ============================================================

# Description
The `SnowmanAirdrop` contract allows users to claim NFTs by providing a cryptographic signature. The current implementation of `getMessageHash()` does not take the claim amount as a parameter — instead, it dynamically queries the user's current token balance using `i_snow.balanceOf(receiver)`.

This creates a front-running opportunity. An attacker monitors the mempool, detects a pending `claimSnowman` transaction, and transfers a minimal amount of Snow tokens (1 wei) to the receiver before it is mined. This changes the receiver's balance, which changes the hash, which invalidates the signature.

```solidity
// src/SnowmanAirdrop.sol

  function getMessageHash(address receiver) public view returns (bytes32) {
    // ...
    // @> Vulnerability: Dynamic balance can be manipulated by a third party
    uint256 amount = i_snow.balanceOf(receiver);

    return _hashTypedDataV4(
        keccak256(abi.encode(MESSAGE_TYPEHASH, SnowmanClaim({receiver: receiver, amount: amount})))
    );
  }
```

# Risk
## Likelihood: Medium
The attack is cheap (1 wei of Snow + gas) and easily automated by monitoring the mempool. Any purchase or transfer can trigger it.

## Impact: High
A malicious actor can permanently prevent any user from claiming their NFTs via the signature mechanism, resulting in a permanent Denial-of-Service.

# Proof of Concept
Alice signs a message for her balance of 1 Snow token. Bob detects her transaction and sends her 1 additional token. When Alice's claim executes, the contract reads a balance of 2 tokens, which does not match her signature for 1 token, causing a revert:

```solidity
function testFinding3_DoSClaimSnowman() public {
    assert(snow.balanceOf(alice) == 1);
    bytes32 alDigest = airdrop.getMessageHash(alice);
    (uint8 alV, bytes32 alR, bytes32 alS) = vm.sign(alKey, alDigest);

    // Attacker front-runs by sending 1 token to Alice
    vm.prank(bob);
    snow.transfer(alice, 1);

    // Alice's claim now reverts
    vm.prank(satoshi);
    vm.expectRevert();
    airdrop.claimSnowman(alice, AL_PROOF, alV, alR, alS);
}
```

# Recommended Mitigation
Include the intended claim `amount` as an explicit parameter in both `getMessageHash` and `claimSnowman`. This ensures the signature is verified against a fixed value that cannot be manipulated by third-party balance changes.

```solidity
function claimSnowman(
    address receiver,
    uint256 amount, // New parameter
    bytes32[] calldata merkleProof,
    uint8 v, bytes32 r, bytes32 s
) external nonReentrant {
    if (!_isValidSignature(receiver, getMessageHash(receiver, amount), v, r, s)) {
        revert SA__InvalidSignature();
    }
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(receiver, amount))));
    // ...
}
```


# ============================================================
# SUBMISSION 4 of 5 — [L-01] Missing Claim Status Check
# ============================================================
# Title: Missing Claim Status Check Allows Multiple Claims in SnowmanAirdrop
# Impact: High
# Likelihood: Medium
# Scope: src/SnowmanAirdrop.sol
# ============================================================

# Description
The `SnowmanAirdrop` contract tracks whether a user has claimed using `s_hasClaimedSnowman`. The `claimSnowman` function correctly sets this mapping to `true` after a successful claim. However, it never checks this value at the beginning of the function.

This means an eligible user can claim an NFT, acquire more Snow tokens (via `earnSnow` or `buySnow`), and then call `claimSnowman` again. As long as they have a valid Merkle proof for their new balance, the contract will process the second claim.

```solidity
// src/SnowmanAirdrop.sol

    function claimSnowman(address receiver, bytes32[] calldata merkleProof, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
    {
        // @> Vulnerability: No check for s_hasClaimedSnowman[receiver] here
        if (receiver == address(0)) {
            revert SA__ZeroAddress();
        }
        // ... (claim logic executes without verifying prior claims)
        s_hasClaimedSnowman[receiver] = true;
    }
```

# Risk
## Likelihood: Medium
Requires the user to acquire additional tokens between claims, which is easily achievable through the protocol's own `earnSnow` mechanism.

## Impact: High
Allows draining the NFT collection and breaks the "one claim per user" distribution model of the airdrop.

# Proof of Concept
Alice claims her first NFT, waits a week to earn more Snow tokens, and then successfully claims a second NFT because the contract never checks if she has already participated:

```solidity
function testMultipleClaimsAllowed() public {
    vm.prank(alice);
    airdrop.claimSnowman(alice, AL_PROOF, v, r, s);
    assert(nft.balanceOf(alice) == 1);

    vm.warp(block.timestamp + 1 weeks);
    vm.prank(alice);
    snow.earnSnow();

    vm.prank(alice);
    airdrop.claimSnowman(alice, AL_PROOF, v2, r2, s2);
    assert(nft.balanceOf(alice) == 2); // Second claim succeeded
}
```

# Recommended Mitigation
Add a check at the start of `claimSnowman` to revert if the user has already claimed.

```diff
// src/SnowmanAirdrop.sol

+ error SA__AlreadyClaimed();

  function claimSnowman(...) external nonReentrant {
+     if (s_hasClaimedSnowman[receiver]) {
+         revert SA__AlreadyClaimed();
+     }
      if (receiver == address(0)) {
          revert SA__ZeroAddress();
      }
      // ...
  }
```


# ============================================================
# SUBMISSION 5 of 5 — [L-02] Global Timer Reset
# ============================================================
# Title: Global Timer Reset in Snow::buySnow Denies Free Claims for All Users
# Impact: High
# Likelihood: Medium
# Scope: src/Snow.sol
# ============================================================

# Description
The `Snow` contract allows users to earn a free token once per week via `earnSnow`. This cooldown is managed by a global variable `s_earnTimer`.

The `buySnow` function resets this global timer to `block.timestamp` every time any user makes a purchase. Because `s_earnTimer` is shared across all users, a single purchase blocks the `earnSnow` function for everyone for another 7 days.

```solidity
// src/Snow.sol

    function buySnow(uint256 amount) external payable canFarmSnow {
        // ... (payment logic)

        // @> Vulnerability: Resets the global timer used by ALL users
        s_earnTimer = block.timestamp;

        emit SnowBought(msg.sender, amount);
    }
```

# Risk
## Likelihood: Medium
Token purchases are expected to happen frequently in a live protocol. A malicious actor could also intentionally buy a single token every 6 days (at minimal cost) to permanently suppress the free claim feature.

## Impact: High
The "free weekly claim" feature, a core incentive for user adoption, becomes completely non-functional. This represents a total Denial-of-Service for a primary protocol function.

# Proof of Concept
User B makes a purchase, which resets the global timer. User A's attempt to earn free tokens now reverts because the contract thinks the cooldown period just started:

```solidity
// User B buys a token, resetting the global timer
snow.buySnow(1);

// User A tries to earn their weekly free token
vm.prank(userA);
vm.expectRevert(Snow.S__Timer.selector);
snow.earnSnow(); // Reverts — timer was just reset by User B
```

# Recommended Mitigation
Remove the global timer reset from `buySnow` and implement a per-user cooldown tracking system using a mapping.

```diff
// src/Snow.sol

+ mapping(address => uint256) private s_lastClaimTime;

  function earnSnow() external canFarmSnow {
-     if (s_earnTimer != 0 && block.timestamp < (s_earnTimer + 1 weeks)) {
+     if (s_lastClaimTime[msg.sender] != 0 && block.timestamp < (s_lastClaimTime[msg.sender] + 1 weeks)) {
          revert S__Timer();
      }
      _mint(msg.sender, 1);
-     s_earnTimer = block.timestamp;
+     s_lastClaimTime[msg.sender] = block.timestamp;
  }

  function buySnow(uint256 amount) external payable canFarmSnow {
      // ... (payment logic)
-     s_earnTimer = block.timestamp;
      emit SnowBought(msg.sender, amount);
  }
```
