## Description
`buySnow` resets the global `s_earnTimer`, blocking `earnSnow` for all users whenever any single user makes a purchase.

```solidity
function buySnow(...) external payable {
    s_earnTimer = block.timestamp; // @> Blocks everyone for 1 week
}
```

## Risk
Likelihood Medium: Any normal purchase resets the timer; a malicious user can block everyone for 1 wei.
Impact High: Complete suppression of the free claim mechanism.

## Proof of Concept
User B's purchase resets the global variable, preventing User A from earning tokens for a week:
```solidity
snow.buySnow(1);
vm.prank(userA);
snow.earnSnow(); // Reverts
```

## Recommended Mitigation
Use a mapping to track `s_lastClaimTime` per user instead of a global timer.
```diff
+ mapping(address => uint256) private s_lastClaimTime;
- if (block.timestamp < s_earnTimer + 1 weeks) revert();
+ if (block.timestamp < s_lastClaimTime[msg.sender] + 1 weeks) revert();
```
