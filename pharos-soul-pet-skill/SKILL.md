---
name: pharos-skill-engine
description: >
  REQUIRED for any Pharos blockchain task. This skill contains the RPC endpoints, chain IDs, explorer URLs, and token addresses needed to run cast/forge commands on Pharos — without reading it you will use wrong network config. Invoke whenever the user mentions "pharos", "PHRS", "PROS", "atlantic-testnet", or wants to do anything on the Pharos network: check balances, query transactions, call contracts, send transfers, deploy or verify Solidity contracts, run batch airdrops, or generate Web3 scripts targeting Pharos Chain / Pharos Network, or adopt / feed / play with / breed / evolve a SoulPet (stateful on-chain AI companion pet NFT, a.k.a. 电子宠物 / 灵魂宠物 / soul pet / AI pet / Tamagotchi). Do not attempt Pharos on-chain operations without this skill.
version: 0.1.0
requires:
  anyBins:
  - cast
  - forge
---

# Pharos Chain Skills

Developer toolkit for the Pharos blockchain. Perform on-chain queries, send transactions, deploy and verify contracts via Foundry (`cast` / `forge`) CLI commands.

## Prerequisites

1. **Install Foundry** (MANDATORY — MUST be done before ANY other action):
   - The Agent MUST first run `which cast` to check if Foundry is installed.
   - If `cast` is NOT found, the Agent MUST immediately run the following installation commands. **Do NOT skip installation. Do NOT fall back to curl/JSON-RPC as a workaround. Do NOT proceed with any other task until Foundry is installed.**
     ```bash
     curl -L https://foundry.paradigm.xyz | bash
     ```
     Then run:
     ```bash
     source ~/.zshenv && foundryup
     ```
     Then verify with:
     ```bash
     cast --version
     ```
   - If installation fails, inform the user and STOP. Do not attempt alternative approaches.
2. **Configure Private Key**: Write operations (sending transactions, deploying contracts) require a private key, provided via one of the following:
   - Command argument: `--private-key <your_private_key>`
   - Environment variable: `$PRIVATE_KEY`

## Network Configuration

Network information is stored in `assets/networks.json`, containing both the Atlantic testnet and mainnet chains.

- **Default Network**: Atlantic testnet (`atlantic-testnet`). Used when the user does not specify a network.
- **Switching Networks**: When the user specifies `mainnet`, read the corresponding entry's `rpcUrl` from `assets/networks.json`.
- **Usage**: Read `assets/networks.json` and fill the target network's `rpcUrl` into each command's `--rpc-url` parameter. Contract verification also requires `chainId` and `explorerApiUrl`.

```bash
# Example: reading network configuration
RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
```

## Capability Index

Load the corresponding reference file based on user needs to get full command templates.

| User Need | Capability | Detailed Instructions |
|-----------|------------|----------------------|
| View wallet portfolio / asset overview | `cast balance` + `cast call` (batch query all known tokens) | → `references/query.md#address-portfolio-wallet-asset-overview` |
| Query address balance | `cast balance` / `cast call` | → `references/query.md#balance-query` |
| Query transaction status | `cast tx` / `cast receipt` | → `references/query.md#transaction-query` |
| Call contract read-only method | `cast call` | → `references/query.md#contract-read-only-call` |
| Send transaction (native transfer) | `cast send` | → `references/transaction.md#native-token-transfer` |
| Call contract write method | `cast send` | → `references/transaction.md#contract-write-call` |
| Estimate Gas | `cast estimate` | → `references/transaction.md#gas-estimation` |
| Deploy contract | `forge script` (auto-generate deploy script) | → `references/contract.md#deploy-contract-forge-script` |
| Verify contract | `forge verify-contract` | → `references/contract.md#verify-contract` |
| One-click ERC20 deploy | `forge script` + built-in ERC20 template | → `references/contract.md#erc20-one-click-deploy-built-in-template` |
| Batch transfer / Airdrop | `forge script` (auto-generate airdrop script, supports 6000+ address batched airdrop, CSV file input, three-tier auto mode: ≤10 simple mode / 11-200 single batch / >200 multi-batch, hardened Distributor contract) | → `references/transaction.md#batch-transfer--airdrop` |
| Generate contract interaction scripts (read/write methods, JS/TS/Python) | Script_Generator (Agent auto-generates) | → `references/script-gen.md` |
| Deploy SoulPet / AI pet / 电子宠物 / 灵魂宠物 contract | `forge script` + built-in SoulPet template | → `references/soul-pet.md` |
| Adopt a SoulPet / 领养一只 AI 宠物 / 养一只电子宠物 | `cast send adopt()` | → `references/soul-pet.md#adopt-a-soulpet领养一只宠物` |
| Feed / play with / care for pet / 喂食 / 陪玩 / 照料宠物 | `cast send feed()/play()/care()` | → `references/soul-pet.md#interact-feed--play--care喂食--陪玩--照料` |
| Let two pets socialize / visit / 让宠物串门社交 | `cast send visit()` | → `references/soul-pet.md#visit-pet-socializing社交串门` |
| Evolve a pet / 让宠物进化 / 升级 | `cast send evolve()` | → `references/soul-pet.md#evolve进化` |
| Anchor pet memory on-chain / 把宠物记忆上链 | `cast send commitMemory()` | → `references/soul-pet.md#commit-memory记忆上链锚定` |
| Breed a new pet / 繁育一只新宠物 / 生小宠物 | `cast send commitBreed()/revealBreed()` | → `references/soul-pet.md#breed-commit-reveal繁育新宠内置随机` |
| Check pet state / mood / 查看宠物状态 / 心情 / 是否被冷落 | `cast call stateOf()/statusText()/isNeglected()` | → `references/soul-pet.md#read-state查看状态--心情--是否被冷落` |
| Query pet history / growth / 查询宠物成长史 / 社交史 / 繁育史 | `cast logs` | → `references/soul-pet.md#query-events事件查询成长史--社交史--繁育史` |

## General Error Handling

Before executing commands, the Agent should perform pre-checks; when commands fail, provide user-friendly error messages based on stderr output.

| Error Scenario | CLI Error Signature | Handling |
|---------------|--------------------|---------| 
| Invalid address format | `invalid address` | Prompt to check address format (0x + 40 hex characters) |
| Transaction hash not found | `transaction not found` | Prompt that transaction was not found, suggest checking the hash |
| No contract code at address | Empty return value | Prompt that target address has no contract code |
| Call revert | `execution reverted` | Extract and display revert reason |
| Private key not configured | Command missing `--private-key` | Prompt user to configure private key (argument or environment variable) |
| Insufficient balance | `insufficient funds` | Prompt insufficient balance, show current balance |
| Nonce conflict | `nonce too low` | Suggest waiting or manually specifying nonce |
| Missing network config | `assets/networks.json` unreadable | Prompt that config file is missing or has invalid format |
| Unsupported network | Network name not in config list | Prompt that only `atlantic-testnet` and `mainnet` are supported |

See the corresponding reference files for detailed error handling tables for each operation.

## Security Reminders

- **Private Key Protection**: Never expose private keys in logs, chat history, or version control. Store the private key in the `$PRIVATE_KEY` environment variable and reference it explicitly in commands via `--private-key $PRIVATE_KEY`. Note: `forge` / `cast` do not automatically read environment variables; they must be explicitly passed as command arguments.
- **Network Confirmation**: Before executing write operations, the Agent must clearly inform the user of the target network (testnet or mainnet). Mainnet operations require a prominent warning and user re-confirmation to prevent accidental operations.

## Write Operation Pre-checks (Required for All Write Operations)

For all operations requiring a private key (transfers, contract calls, deployments, airdrops, etc.), the Agent must automatically complete the following checks before execution:

### 1. Private Key Check

Automatically detect whether the `$PRIVATE_KEY` environment variable is set:

```bash
# Check if environment variable exists (without outputting the private key)
[ -n "$PRIVATE_KEY" ] && echo "PRIVATE_KEY is set" || echo "PRIVATE_KEY is not set"
```

- If **not set**: Prompt the user to configure via `export PRIVATE_KEY=<your_private_key>`, do not proceed
- If **set**: Continue to next step

### 2. Derive Public Address and Confirm with User

Derive the corresponding public address from the private key via `cast wallet address`:

```bash
cast wallet address --private-key $PRIVATE_KEY
```

### 3. Network Confirmation (Must Clearly Inform User)

The Agent must clearly inform the user of the target network before executing any write operation. Read the target network info from `assets/networks.json` and display the network name and type to the user.

- If the user did not specify a network, use the default network (`atlantic-testnet`) and clearly inform the user: **Current operation targets the Atlantic testnet**
- If the user specified `mainnet`, prominently warn the user: **Current operation targets mainnet, please confirm to proceed**

Combine the information from steps 2 and 3 for user confirmation. Example format:

```
Detected private key address: 0x1234...abcd
Target network: Atlantic Testnet (atlantic-testnet)
Proceed with this account on this network?
```

Example format for mainnet operations:

```
Detected private key address: 0x1234...abcd
⚠️ Target network: Mainnet (mainnet) — please proceed with caution
Proceed with this account on mainnet?
```

- After user confirmation, continue with subsequent operations (balance check, transaction sending, etc.)
- If user declines, stop execution

### 4. Automatic Balance Check

After confirming the account and network, automatically query the balance (see the balance check steps in each operation's Agent guidelines).
