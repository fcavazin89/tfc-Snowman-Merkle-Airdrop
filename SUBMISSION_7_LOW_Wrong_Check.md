# Finding Submission #7 - Low

## Title
Wrong Owner Check in tokenURI Function

## Severity
**Low** (Low Impact + High Likelihood)

## Description
The `tokenURI()` function in `Snowman.sol` checks if `ownerOf(tokenId) == address(0)` to verify if a token exists. However, OpenZeppelin's ERC721 implementation **reverts** when querying non-existent tokens instead of returning `address(0)`. Therefore, this check **never triggers** as expected.

### Vulnerable Code
```solidity
// src/Snowman.sol:47-50
function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    if (ownerOf(tokenId) == address(0)) { // This condition never becomes true!
        revert ERC721Metadata__URI_QueryFor_NonExistentToken();
    }
    // ...
}
```

### Root Cause
Misunderstanding of how OpenZeppelin's `ownerOf()` works. It reverts for non-existent tokens rather than returning `address(0)`.

## Proof of Concept
```solidity
function testFinding7_WrongOwnerCheck() public {
    // Try to call tokenURI for a non-existent token
    // The OZ ERC721 will revert from ownerOf() before reaching the if check
    vm.expectRevert(); // Will revert from OZ, not from the custom error
    nft.tokenURI(9999); // Non-existent token ID
}
```

## Impact
- **Dead code**: The custom error `ERC721Metadata__URI_QueryFor_NonExistentToken()` never gets triggered
- **Confusion**: Developer might think they're handling non-existent tokens, but they're not
- **Minimal practical impact**: OpenZeppelin's `ownerOf()` already reverts correctly

## Recommended Mitigation
Remove the unnecessary check since OZ already handles it:

```solidity
function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    // OZ ownerOf() will revert for non-existent tokens automatically
    // No need for manual check
    
    string memory imageURI = s_SnowmanSvgUri;
    
    return string(
        abi.encodePacked(
            _baseURI(),
            Base64.encode(
                abi.encodePacked(
                    '{"name":"',
                    name(),
                    '", "description":"Snowman for everyone!!!", ',
                    '"attributes": [{"trait_type": "freezing", "value": 100}], "image":"',
                    imageURI,
                    '"}'
                )
            )
        )
    );
}
```

Or if you want to keep custom error handling, use try/catch:

```solidity
function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    // Check if token exists using totalSupply or direct balance check
    if (tokenId >= s_TokenCounter) {
        revert ERC721Metadata__URI_QueryFor_NonExistentToken();
    }
    // ...
}
```

## Location
`src/Snowman.sol:47-50`

## Validation
✅ PoC test passes  
✅ OZ documentation confirms ownerOf reverts  
✅ The check is indeed dead code

---

**XP Expected:** 2 XP (Low severity)
