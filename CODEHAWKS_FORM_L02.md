# Description
The `Snow` contract includes an `earnSnow` function that allows users to claim a free token once per week. This cooldown is managed by a variable called `s_earnTimer`.

A critical flaw exists in the `buySnow` function. Every time a user purchases tokens (an action that can be performed at any time by anyone), the global `s_earnTimer` is reset to the current `block.timestamp`.

```solidity
// src/Snow.sol

    function buySnow(uint256 amount) external payable canFarmSnow {
        // ... (payment logic)
        
        // @> Vulnerability: Resets the global timer used by ALL users.
        s_earnTimer = block.timestamp;

        emit SnowBought(msg.sender, amount);
    }
```

Because `s_earnTimer` is a global variable and not tracked on a per-user basis, a single purchase by any user resets the 1-week cooldown for every other user in the protocol.

# Risk
## Likelihood: Medium
In a live protocol, token purchases are expected to happen frequently. Every purchase naturally resets the timer for everyone. Furthermore, a malicious actor could intentionally buy a single token every 6 days to permanently block all other users from ever using the `earnSnow` feature.

## Impact: High
The "free weekly claim" feature, a core incentive for user adoption, is rendered completely non-functional. This represents a total Denial-of-Service for a primary protocol function and violates the documented tokenomics of the project.

# Proof of Concept
The following scenario illustrates the global blockage. User A is eligible to earn tokens, but User B makes a purchase just before User A can claim. This resets the timer, forcing User A to wait another week.

```solidity
// User A is ready to earn their weekly token
// But User B makes a purchase, resetting the global timer
snow.buySnow(1); 

// User A's attempt to earn tokens now reverts
vm.prank(userA);
vm.expectRevert(Snow.S__Timer.selector);
snow.earnSnow(); 
```

# Recommended Mitigation
Remove the global timer reset from the `buySnow` function and implement a per-user cooldown tracking system using a mapping.

```diff
// src/Snow.sol

+ mapping(address => uint256) private s_lastClaimTime;

  function earnSnow() external canFarmSnow {
-     if (s_earnTimer != 0 && block.timestamp < (s_earnTimer + 1 weeks)) {
+     if (s_lastClaimTime[msg.sender] != 0 && block.timestamp < (s_lastClaimTime[msg.sender] + 1 weeks)) {
          revert S__Timer();
      }
      _mint(msg.sender, 1);
+     s_lastClaimTime[msg.sender] = block.timestamp;
-     s_earnTimer = block.timestamp;
  }

  function buySnow(uint256 amount) external payable canFarmSnow {
      // ...
-     s_earnTimer = block.timestamp;
  }
```
