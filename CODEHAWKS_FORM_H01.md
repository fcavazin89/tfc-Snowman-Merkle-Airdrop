## Description
`Snowman::mintSnowman()` lacks access control. Any address can mint unlimited NFTs without staking, bypassing protocol mechanics.

```solidity
function mintSnowman(address receiver, uint256 amount) external { // @> No access control
    for (uint256 i = 0; i < amount; i++) {
        _safeMint(receiver, s_TokenCounter);
        s_TokenCounter++;
    }
}
```

## Risk
Likelihood High: No costs or conditions are required to execute the attack.
Impact High: Infinite inflation destroys the NFT's value and renders the staking system useless.

## Proof of Concept
An unauthorized attacker mints 100 NFTs for free without staking any tokens:
```solidity
function testExploit() public {
    vm.prank(attacker);
    nft.mintSnowman(attacker, 100);
    assert(nft.balanceOf(attacker) == 100);
}
```

## Recommended Mitigation
Restrict `mintSnowman` to the authorized airdrop contract via a modifier.
```diff
+ modifier onlyAirdrop() { if (msg.sender != s_airdropContract) revert(); _; }
- function mintSnowman(...) external {
+ function mintSnowman(...) external onlyAirdrop {
```
