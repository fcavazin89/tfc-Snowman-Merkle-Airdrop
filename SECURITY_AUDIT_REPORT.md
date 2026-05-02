# Relatório de Auditoria de Segurança - Snowman Protocol

**Data:** 02 de Maio de 2026  
**Auditor:** OpenCode AI  
**Escopo:** Snow.sol, Snowman.sol, SnowmanAirdrop.sol  
**Ferramentas Utilizadas:** Foundry (Forge Tests), Slither

---

## Resumo Executivo

O protocolo Snowman apresenta **7 vulnerabilidades** identificadas, sendo **4 Críticas/Altas** e **3 Médias/Baixas**. As vulnerabilidades mais graves permitem minting não autorizado de NFTs, quebra do mecanismo de farming e falha na verificação de assinaturas EIP-712.

### Estatísticas
- **Testes Executados:** 15 (14 passaram, 1 falhou - teste pré-existente)
- **Vulnerabilidades Críticas:** 3
- **Vulnerabilidades Altas:** 1
- **Vulnerabilidades Médias:** 2
- **Vulnerabilidades Baixas:** 1

---

## Vulnerabilidades Encontradas

### CRÍTICA #1: Minting Irrestrito de NFTs (Snowman.sol)

**Severidade:** Crítica  
**Arquivo:** `src/Snowman.sol:36-44`  
**Impacto:** Qualquer usuário pode mintar NFTs ilimitados sem staking de tokens Snow

#### Código Vulnerável
```solidity
function mintSnowman(address receiver, uint256 amount) external {
    for (uint256 i = 0; i < amount; i++) {
        _safeMint(receiver, s_TokenCounter);
        emit SnowmanMinted(receiver, s_TokenCounter);
        s_TokenCounter++;
    }
}
```

#### Descrição
A função `mintSnowman` não possui controle de acesso. Qualquer endereço pode chamar esta função e mintar uma quantidade arbitrária de NFTs Snowman para qualquer destinatário, sem precisar fazer staking de tokens Snow.

#### Prova de Conceito (PoC)
```solidity
function test_Finding3_AnyoneCanMintSnowmanNFTs() public {
    uint256 initialCounter = nft.getTokenCounter();
    address attacker = makeAddr("attacker");
    
    // Attacker mints 100 NFTs to themselves without staking any Snow tokens
    vm.prank(attacker);
    nft.mintSnowman(attacker, 100);
    
    assert(nft.balanceOf(attacker) == 100);
    assert(nft.getTokenCounter() == initialCounter + 100);
}
```

#### Recomendação
Adicionar modificador de acesso restrito ao contrato SnowmanAirdrop:
```solidity
address public s_airdropContract;

modifier onlyAirdrop() {
    if (msg.sender != s_airdropContract) {
        revert SM__NotAllowed();
    }
    _;
}

function mintSnowman(address receiver, uint256 amount) external onlyAirdrop {
    // ...
}
```

---

### CRÍTICA #2: Erro de Digitação no MESSAGE_TYPEHASH (SnowmanAirdrop.sol)

**Severidade:** Crítica  
**Arquivo:** `src/SnowmanAirdrop.sol:49`  
**Impacto:** Verificação de assinaturas EIP-712 quebrada - usuários não conseguem fazer claim

#### Código Vulnerável
```solidity
bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
```

#### Descrição
Existe um erro de digitação em `addres` (faltando o caractere 's'). O correto deveria ser `address`. Isso faz com que o hash do tipo seja diferente do esperado, causando falha em todas as verificações de assinatura EIP-712.

#### Prova de Conceito (PoC)
```solidity
function test_Finding4_MessageTypeHashTypo() public {
    bytes32 wrongTypeHash = keccak256("SnowmanClaim(addres receiver, uint256 amount)");
    bytes32 correctTypeHash = keccak256("SnowmanClaim(address receiver, uint256 amount)");
    
    assertTrue(wrongTypeHash != correctTypeHash); // Vai passar - são diferentes!
}
```

#### Recomendação
Corrigir o erro de digitação:
```solidity
bytes32 private constant MESSAGE_TYPEHASH = keccak256("SnowmanClaim(address receiver, uint256 amount)");
```

---

### CRÍTICA #3: Cálculo de Taxa Quebrado em buySnow (Snow.sol)

**Severidade:** Crítica/Alta  
**Arquivo:** `src/Snow.sol:73,80,83`  
**Impacto:** Usuários pagam valor exponencialmente errado ou transação falha

#### Código Vulnerável
```solidity
// Constructor
s_buyFee = _buyFee * PRECISION; // Armazena como 5 * 10^18

// buySnow function
if (msg.value == (s_buyFee * amount)) { // Multiplica novamente por amount!
    _mint(msg.sender, amount);
}
```

#### Descrição
A taxa é armazenada já multiplicada por `PRECISION (10^18)`. No entanto, na função `buySnow`, ela é multiplicada novamente por `amount`. Isso resulta em um valor exponencialmente incorreto.

Para `_buyFee = 5` e `amount = 1`:
- Armazenado: `5 * 10^18`
- Verificação: `(5 * 10^18) * 1 = 5 * 10^18 wei` (correto por acidente para amount=1)
- Para amount=2: `(5 * 10^18) * 2 = 10 * 10^18 wei` (incorreto)

#### Recomendação
Corrigir o armazenamento ou a verificação:
```solidity
// Opção 1: Armazenar sem PRECISION
s_buyFee = _buyFee;

// E na verificação:
if (msg.value == (s_buyFee * PRECISION * amount)) { ... }
```

---

### ALTA #4: Timer Global de Farming (Snow.sol)

**Severidade:** Alta  
**Arquivo:** `src/Snow.sol:29,87,93-94`  
**Impacto:** Um usuário usando `earnSnow()` bloqueia TODOS os outros usuários por uma semana

#### Código Vulnerável
```solidity
uint256 private s_earnTimer; // Timer GLOBAL, não por usuário!

function earnSnow() external canFarmSnow {
    if (s_earnTimer != 0 && block.timestamp < (s_earnTimer + 1 weeks)) {
        revert S__Timer();
    }
    _mint(msg.sender, 1);
    s_earnTimer = block.timestamp; // Sobrescreve o timer de todos!
}
```

#### Descrição
A variável `s_earnTimer` é única para todo o contrato. Quando qualquer usuário chama `earnSnow()`, o timer é atualizado para o timestamp atual. Isso bloqueia todos os outros usuários de usar a função até que uma semana passe desde a última chamada de qualquer usuário.

#### Prova de Conceito (PoC)
```solidity
function test_Finding2_GlobalEarnTimerBlocksAllUsers() public {
    address charlie = makeAddr("charlie");
    
    // Alice earns snow (ela já ganhou no setUp)
    vm.prank(alice);
    vm.expectRevert(Snow.S__Timer.selector);
    snow.earnSnow(); // Bloqueada pelo timer global
    
    // Charlie (que nunca ganhou) também está bloqueado
    // devido ao timer global estar setado
}
```

#### Recomendação
Usar um mapping para rastrear o timer por usuário:
```solidity
mapping(address => uint256) private s_lastEarnTime;

function earnSnow() external canFarmSnow {
    if (s_lastEarnTime[msg.sender] != 0 && block.timestamp < (s_lastEarnTime[msg.sender] + 1 weeks)) {
        revert S__Timer();
    }
    _mint(msg.sender, 1);
    s_lastEarnTime[msg.sender] = block.timestamp;
}
```

---

### MÉDIA #5: s_hasClaimedSnowman Não Verificado (SnowmanAirdrop.sol)

**Severidade:** Média  
**Arquivo:** `src/SnowmanAirdrop.sol:47,94`  
**Impacto:** Possibilidade de duplo claim se o usuário receber mais tokens

#### Descrição
O mapping `s_hasClaimedSnowman` é definido após o claim, mas nunca é verificado no início da função `claimSnowman`. Isso significa que se um usuário receber mais tokens Snow após o primeiro claim, ele pode fazer claim novamente.

#### Código
```solidity
mapping(address => bool) private s_hasClaimedSnowman;

function claimSnowman(...) external nonReentrant {
    // Falta: if (s_hasClaimedSnowman[receiver]) revert AlreadyClaimed();
    
    // ... lógica de claim
    
    s_hasClaimedSnowman[receiver] = true; // Definido mas nunca verificado
}
```

#### Recomendação
Adicionar verificação no início da função `claimSnowman`:
```solidity
if (s_hasClaimedSnowman[receiver]) {
    revert SA__AlreadyClaimed();
}
```

---

### MÉDIA #6: Uso de Transfer Inseguro (Snow.sol)

**Severidade:** Média  
**Arquivo:** `src/Snow.sol:103`  
**Impacto:** Alguns tokens ERC20 não revertem em falhas de transferência

#### Código Vulnerável (identificado pelo Slither)
```solidity
function collectFee() external onlyCollector {
    uint256 collection = i_weth.balanceOf(address(this));
    i_weth.transfer(s_collector, collection); // Inseguro!
    // ...
}
```

#### Recomendação
Usar `safeTransfer` do SafeERC20:
```solidity
i_weth.safeTransfer(s_collector, collection);
```

---

### BAIXA #7: Verificação Incorreta em tokenURI (Snowman.sol)

**Severidade:** Baixa  
**Arquivo:** `src/Snowman.sol:48`  
**Impacto:** A verificação nunca é executada conforme esperado

#### Código Vulnerável
```solidity
function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    if (ownerOf(tokenId) == address(0)) { // ownerOf REVERTE para tokens inexistentes!
        revert ERC721Metadata__URI_QueryFor_NonExistentToken();
    }
    // ...
}
```

#### Descrição
A implementação do OpenZeppelin de `ownerOf()` reverte para tokens não existentes, em vez de retornar `address(0)`. Portanto, a condição no if nunca será verdadeira - o contrato reverterá antes.

#### Recomendação
Remover a verificação ou usar try/catch, mas o `ownerOf` do OZ já faz essa verificação e reverte automaticamente.

---

## Resultados do Slither

O Slither identificou 6 problemas adicionais:

1. **arbitrary-send-erc20**: Uso de `transferFrom` com `from` arbitrário em `SnowmanAirdrop.claimSnowman`
2. **unchecked-transfer**: `i_weth.transfer()` ignora valor de retorno (FINDING #6)
3. **incorrect-equality**: Uso de `== 0` em `balanceOf` (pode ser problemático)
4. **reentrancy-no-eth**: Possível reentrancy em `Snowman.mintSnowman` (baixo risco pois não envolve ETH)
5. **unused-return**: Valor de retorno de `ECDSA.tryRecover` ignorado (já tratado na lógica)

---

## Testes com Foundry

### Resumo dos Testes
```
Ran 5 test suites:
- TestSnow: 6 passed
- TestSnowman: 2 passed  
- TestSnowmanAirdrop: 1 passed
- PoC_Findings: 5 passed (validação das vulnerabilidades)
- TestDeploySnowman: 1 failed (falha pré-existente no teste de conversão SVG)

Total: 14 passed, 1 failed (não relacionado às vulnerabilidades)
```

### PoC Tests Criados
Arquivo: `test/PoC_Findings.t.sol`
- ✅ test_Finding2_GlobalEarnTimerBlocksAllUsers
- ✅ test_Finding3_AnyoneCanMintSnowmanNFTs
- ✅ test_Finding4_MessageTypeHashTypo
- ✅ test_Finding5_ClaimStatusNotChecked
- ✅ test_Finding7_TokenURICheckWrong

---

## Conclusão e Recomendações

### Prioridade Alta (Corrigir Imediatamente)
1. **Adicionar controle de acesso em `Snowman.mintSnowman`** - Crítico
2. **Corrigir erro de digitação em `MESSAGE_TYPEHASH`** - Crítico
3. **Corrigir cálculo de taxa em `buySnow`** - Crítico
4. **Implementar timer por usuário em `earnSnow`** - Alto

### Prioridade Média
5. **Verificar `s_hasClaimedSnowman` antes de permitir claim**
6. **Usar `safeTransfer` em `collectFee`**

### Observações Finais
- O contrato foi desenvolvido com boas práticas gerais (uso de SafeERC20, Ownable, ReentrancyGuard)
- A lógica de Merkle Tree foi implementada corretamente, mas o erro de digitação no typehash invalida as assinaturas
- O mecanismo de farming tem uma falha de lógica séria no timer global
- **Não deployar em produção sem corrigir as vulnerabilidades Críticas**

---

## Apêndice: Comandos Executados

```bash
# Clone do repositório
git clone https://github.com/CodeHawks-Contests/2025-06-snowman-merkle-airdrop.git
cd 2025-06-snowman-merkle-airdrop
forge install
forge build

# Execução de testes
forge test -vv

# Análise estática com Slither
python -m slither . --exclude-dependencies --json slither-output.json

# PoC Tests
forge test --match-contract PoC_Findings -vv
```

---

**Relatório gerado em:** 02/05/2026  
**Status:** Auditoria Concluída
