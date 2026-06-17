# SoulPet Operation Instructions（有状态 AI 伴侣宠物操作手册）

本文件是 Agent 在用户操作 SoulPet（链上 AI 电子宠物）时读取的指令手册。SoulPet 是一个**完全自包含**的单合约：饥饿、心情、亲密度、进化阶段、性格基因全部为链上状态，并内置 commit-reveal + 区块熵的繁育随机，不依赖任何外部预言机或库。

> **正文用中文便于人类阅读；命令模板、函数签名、事件签名与 revert 字符串保持英文原样，请勿翻译，否则 CLI 无法工作。**

> **Network Configuration**：所有命令中的 `<rpc>` 从 `assets/networks.json` 中对应网络的 `rpcUrl` 读取，默认 Atlantic 测试网。`--rpc-url` 必须显式传入，否则 `forge` / `cast` 会默认连 `localhost:8545` 而失败。
>
> **Private Key Configuration**：所有写操作必须通过 `--private-key` 显式传入私钥，推荐 `--private-key $PRIVATE_KEY`。`forge` / `cast` 不会自动读取环境变量。

合约源码位于 `assets/soul-pet/SoulPet.sol`。附身 Agent 演示脚本位于 `assets/soul-pet/agent/soulpet_agent.py`。

合约关键常量（影响交互判断）：

| 常量 | 值 | 含义 |
|------|----|------|
| `FEED_COOLDOWN` | 1 hour | 两次喂食最小间隔 |
| `HUNGER_PER_HOUR` | 5 | 每小时饥饿增长 |
| `MOOD_DROP_PER_HOUR` | 3 | 每小时心情下降 |
| `NEGLECT_THRESHOLD` | 2 days | 超过此时长未互动即"被冷落" |
| `BREED_MIN_AFFINITY` | 100 | 繁育所需最低亲密度 |
| `MAX_STAGE` | 4 | 最高进化阶段 |
| 睡眠时间窗 | UTC 22:00–06:00 | 该时段 `feed`/`play`/`visit` 会 revert `Pet is sleeping` |

---

## Deploy SoulPet（部署宠物合约）

### Overview

SoulPet 构造函数无参数，部署后即可领养。部署脚本位于 `assets/soul-pet/`，Agent 应将合约复制进用户项目后生成部署脚本并执行。

### Step 1: Generate Deployment Script

在用户项目 `script/` 下生成 `DeploySoulPet.s.sol`：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/soul-pet/SoulPet.sol";

contract DeploySoulPet is Script {
    function run() external {
        vm.startBroadcast();
        SoulPet soulPet = new SoulPet();
        console.log("=== Deploy Result ===");
        console.log("SoulPet address:", address(soulPet));
        console.log("Deployer:", msg.sender);
        vm.stopBroadcast();
    }
}
```

### Step 2: Execute Deployment

**Command Template**

```bash
forge script script/DeploySoulPet.s.sol:DeploySoulPet \
  --rpc-url <rpc> \
  --private-key $PRIVATE_KEY \
  --broadcast
```

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `--rpc-url` | string | Yes | RPC 端点，读自 `assets/networks.json` |
| `--private-key` | string | Yes | 部署者私钥，使用 `$PRIVATE_KEY` |

**Output Parsing**

| Field | Description |
|---|---|
| `SoulPet address:` | 已部署合约地址 —— 后续所有交互都用它 |
| `Deployer:` | 部署者地址 |

**Error Handling**

| Error | Cause | Fix |
|---|---|---|
| `compiler error` | 编译失败 | 检查源码路径与 Foundry 版本（`^0.8.20`） |
| `insufficient funds` | gas 不足 | `cast balance <deployer> --rpc-url <rpc> --ether` |
| `connection refused` | 缺少或错误的 `--rpc-url` | 确认显式传入 `--rpc-url` |

> **Agent Guidelines:**
> 1. 完成 SKILL.md 中的"Write Operation Pre-checks"
> 2. 把 `assets/soul-pet/SoulPet.sol` 复制到用户项目 `src/soul-pet/SoulPet.sol`
> 3. 检查部署者余额：`cast balance <deployer> --rpc-url <rpc> --ether`
> 4. 从 `assets/networks.json` 读取 `rpcUrl`
> 5. 生成 `script/DeploySoulPet.s.sol` 并执行 `forge script ... --broadcast`
> 6. 从输出提取合约地址，展示浏览器链接：`<explorerUrl>/address/<address>`
> 7. 询问是否验证合约；若是，先 `sleep 10` 再验证

---

## Verify SoulPet（验证合约）

**Command Template**

```bash
sleep 10
forge verify-contract <soulpet_address> src/soul-pet/SoulPet.sol:SoulPet \
  --chain-id <chain_id> \
  --verifier-url <explorer_api_url>/v1/explorer/command_api/contract \
  --verifier blockscout
```

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `<soulpet_address>` | string | Yes | 已部署合约地址 |
| `<chain_id>` | number | Yes | 读自 `assets/networks.json` 的 `chainId` |
| `<explorer_api_url>` | string | Yes | 读自 `assets/networks.json` 的 `explorerApiUrl` |

> **注意**：SoulPet 构造函数无参数，验证时**无需** `--constructor-args`。

**Error Handling**

| Error | Cause | Fix |
|---|---|---|
| `contract not found` | 浏览器尚未索引 | 等待 10–15 秒后重试 |
| `verification failed` | 源码/编译器不匹配 | 确认 Solidity 版本一致 |

---

## Adopt a SoulPet（领养一只宠物）

### Overview

领养一只全新的 SoulPet（从"蛋"阶段开始）。`traits` 为 32 字节性格基因，影响 AI 附身语气，并在繁育时与配偶混合。

**Command Template**

```bash
cast send <soulpet_address> "adopt(bytes32)" <traits> \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `<soulpet_address>` | string | Yes | 合约地址 |
| `<traits>` | bytes32 | Yes | 性格基因，32 字节十六进制（如 `0x01`，会自动左补零） |

**Output Parsing**

| Field | Description |
|---|---|
| `status` | `1`=成功，`0`=失败 |
| `transactionHash` | 用于查 `Adopted(owner,id,traits)` 事件，从中获取新宠 `id` |

**Error Handling**

| Error | Cause | Fix |
|---|---|---|
| `PRIVATE_KEY not set` | 未配置私钥 | `export PRIVATE_KEY=0x...` |
| `insufficient funds` | gas 不足 | `cast balance` 检查余额 |

> **Agent Guidelines:**
> 1. 完成"Write Operation Pre-checks"
> 2. 若用户未提供 `traits`，可随机生成一个 32 字节值（如 `cast keccak <随机串>`）
> 3. 发送交易后，用 `cast logs` 查 `Adopted` 事件解析出新宠 `id` 并告知用户
> 4. 展示交易链接 `<explorerUrl>/tx/<txHash>`

---

## Interact: Feed / Play / Care（喂食 / 陪玩 / 照料）

### Overview

三种互动都会提升亲密度并影响心情：
- `feed(uint256)`：**有 1 小时冷却**，清空饥饿、心情 +15、亲密度 +5；可附带 `--value` 作为零食。
- `play(uint256)`：无冷却，心情 +20、亲密度 +8、饥饿 +5。
- `care(uint256)`：无冷却、无睡眠限制，心情 +10、亲密度 +3。

> `feed` 与 `play` 在睡眠时间窗（UTC 22:00–06:00）会 revert `Pet is sleeping`；`care` 不受睡眠限制。

**Command Template**

```bash
# 喂食（可选附带零食）
cast send <soulpet_address> "feed(uint256)" <id> \
  --value <amount>ether \
  --private-key $PRIVATE_KEY --rpc-url <rpc>

# 陪玩
cast send <soulpet_address> "play(uint256)" <id> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>

# 照料
cast send <soulpet_address> "care(uint256)" <id> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `<id>` | uint256 | Yes | 宠物 id |
| `--value` | flag | No | 仅 `feed` 可选，附带的 PHRS 零食金额，如 `0.01ether` |

**Output Parsing**

| Field | Description |
|---|---|
| `status` | `1`=成功 |
| `transactionHash` | 用于查 `Interacted(id, kind)` 事件，`kind`：0=feed，1=play，2=care |

**Error Handling**

| Error Signature | Cause | Suggested Action |
|---|---|---|
| `execution reverted: Too soon to feed` | 距上次喂食不足 1 小时 | 先 `cast call` 查状态，提示用户稍后再喂或改用 `play`/`care` |
| `execution reverted: Pet is sleeping` | 处于 UTC 22:00–06:00 睡眠窗 | 告知宠物在睡觉，建议改用 `care` 或稍后再来 |
| `execution reverted: Not pet owner` | 私钥非该宠物主人 | 确认 `$PRIVATE_KEY` 与 `ownerOf(id)` 一致 |
| `execution reverted: Pet does not exist` | id 不存在 | 确认宠物 id 是否正确 |

> **Agent Guidelines:**
> 1. 完成"Write Operation Pre-checks"
> 2. 互动前先 `cast call statusText(uint256)` 读取宠物情绪，用宠物口吻向用户转述
> 3. 喂食前若担心冷却，可先读 `stateOf` 判断；遇 `Too soon to feed` 改建议 `play`/`care`
> 4. 互动成功后再次读取 `stateOf`，展示心情/亲密度变化与交易链接

---

## Visit: Pet Socializing（社交串门）

### Overview

让自己的宠物去拜访另一只宠物，双方心情各 +12、亲密度各 +4，是撮合主人社交的入口。

**Command Template**

```bash
cast send <soulpet_address> "visit(uint256,uint256)" <id> <otherId> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `<id>` | uint256 | Yes | 自己的宠物（必须由调用者拥有） |
| `<otherId>` | uint256 | Yes | 被拜访的宠物 |

**Output Parsing**

| Field | Description |
|---|---|
| `transactionHash` | 用于查 `Visited(id, otherId)` 事件 |

**Error Handling**

| Error Signature | Cause | Suggested Action |
|---|---|---|
| `execution reverted: Cannot visit self` | id 与 otherId 相同 | 选择另一只宠物 |
| `execution reverted: Other pet does not exist` | otherId 不存在 | 确认对方宠物 id |
| `execution reverted: Pet is sleeping` | 睡眠时间窗 | 稍后再串门 |
| `execution reverted: Not pet owner` | 不拥有 `id` | 确认私钥归属 |

> **Agent Guidelines:**
> 1. 完成"Write Operation Pre-checks"
> 2. 串门成功后读取双方 `stateOf`，向用户展示双方心情提升
> 3. 可建议两位主人后续一起繁育（见下文 Breed）

---

## Evolve（进化）

### Overview

满足条件时进化到下一阶段。条件（`nextStage = stage + 1`）：年龄 ≥ `birth + 1 day × nextStage`、累计亲密度 ≥ `50 × nextStage`、当前心情 ≥ 50。任何人都可触发（通常由附身 Agent 自动调用）。

**Command Template**

```bash
cast send <soulpet_address> "evolve(uint256)" <id> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

**Output Parsing**

| Field | Description |
|---|---|
| `transactionHash` | 用于查 `Evolved(id, stage)` 事件，得到新阶段 |

**Error Handling**

| Error Signature | Cause | Suggested Action |
|---|---|---|
| `execution reverted: Already max stage` | 已达 `MAX_STAGE`(4) | 告知已是最终形态 |
| `execution reverted: Too young to evolve` | 年龄不足 | 读 `stateOf` 与出生时间，提示还需等待 |
| `execution reverted: Affinity too low to evolve` | 亲密度不足 | 建议多 `feed`/`play`/`care` 提升亲密度 |
| `execution reverted: Mood too low to evolve` | 心情 < 50 | 先陪玩/照料把心情养上去 |

> **Agent Guidelines:**
> 1. 完成"Write Operation Pre-checks"
> 2. 进化前先 `cast call stateOf` 检查年龄/亲密度/心情是否达标，避免无谓 revert
> 3. 进化成功后展示 `Evolved` 事件与新阶段

---

## Commit Memory（记忆上链锚定）

### Overview

把本次对话/记忆的 Merkle 根写到链上（细节存链下，链上仅锚定，体现"灵魂状态上链、记忆细节链下可验证"）。通常由附身 Agent 调用。

**Command Template**

```bash
cast send <soulpet_address> "commitMemory(uint256,bytes32)" <id> <memoryRoot> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `<id>` | uint256 | Yes | 宠物 id |
| `<memoryRoot>` | bytes32 | Yes | 链下记忆的 Merkle 根 |

**Output Parsing**

| Field | Description |
|---|---|
| `transactionHash` | 用于查 `MemoryUpdated(id, root)` 事件 |

> **Agent Guidelines:**
> 1. 完成"Write Operation Pre-checks"
> 2. 由附身 Agent 在重要对话后调用；`memoryRoot` 由链下记忆树计算
> 3. 仅宠物主人可写入（`Not pet owner`）

---

## Breed: Commit-Reveal（繁育新宠，内置随机）

### Overview

两阶段繁育，自包含随机（commit-reveal + 区块熵 `block.prevrandao`）：双方亲密度均需 ≥ 100。
1. `commitBreed(idA, idB, commitHash)`：提交承诺，`commitHash = keccak256(abi.encodePacked(seed, salt))`，`seed`/`salt` 链下保密。
2. `revealBreed(idA, idB, seed, salt)`：揭示并产出子代，子代基因 = `keccak256(seed, salt, block.prevrandao, parentA.traits, parentB.traits)`。

> 黑客松版要求 `idA`、`idB` 均由调用者拥有。该随机**非密码学级 VRF**，仅供演示。

**Command Template**

```bash
# 1) 链下生成 seed/salt 与 commitHash（示例）
SEED=$(cast keccak "my-secret-seed")
SALT=$(cast keccak "my-secret-salt")
COMMIT=$(cast keccak $(cast abi-encode "f(bytes32,bytes32)" $SEED $SALT))
# 注意：合约用的是 abi.encodePacked，请改用 packed 编码，见 Agent Guidelines

# 2) 提交承诺
cast send <soulpet_address> "commitBreed(uint256,uint256,bytes32)" <idA> <idB> <commitHash> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>

# 3) 揭示并繁育
cast send <soulpet_address> "revealBreed(uint256,uint256,bytes32,bytes32)" <idA> <idB> <seed> <salt> \
  --private-key $PRIVATE_KEY --rpc-url <rpc>
```

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `<idA>` / `<idB>` | uint256 | Yes | 双亲宠物 id（均需调用者拥有、亲密度 ≥ 100） |
| `<commitHash>` | bytes32 | Yes | `keccak256(abi.encodePacked(seed, salt))` |
| `<seed>` / `<salt>` | bytes32 | Yes | 与承诺一致的揭示值 |

**Output Parsing**

| Field | Description |
|---|---|
| `transactionHash` | 用于查 `Bred(parentA, parentB, childId)` 事件，得到子代 id |

**Error Handling**

| Error Signature | Cause | Suggested Action |
|---|---|---|
| `execution reverted: Affinity too low to breed` | 任一方亲密度 < 100 | 先多互动提升双方亲密度 |
| `execution reverted: Cannot breed with self` | idA == idB | 选择两只不同宠物 |
| `execution reverted: Breed not committed` | 未先 commit | 先调用 `commitBreed` |
| `execution reverted: Breed not revealed` | seed/salt 与承诺不符 | 确认与 commit 时一致的 seed/salt |
| `execution reverted: Not pet owner` | 非双方主人 | 确认私钥同时拥有 idA 与 idB |

> **Agent Guidelines:**
> 1. 完成"Write Operation Pre-checks"
> 2. 计算 `commitHash` 时**必须用 packed 编码**与合约一致：`cast keccak $(cast concat-hex $SEED $SALT)`（两个 32 字节直接拼接），不要用 `abi-encode`
> 3. 先读 `stateOf` 确认双方亲密度 ≥ 100，再 commit
> 4. commit 后再发送 reveal；reveal 成功后查 `Bred` 事件解析子代 id 并展示其 `stateOf`

---

## Read State（查看状态 / 心情 / 是否被冷落）

### Overview

只读视图（免费、无需 gas），供 Agent 感知宠物情绪后决定语气。

**Command Template**

```bash
# 实时数值状态：owner, hunger, mood, affinity, stage, traits
cast call <soulpet_address> \
  "stateOf(uint256)(address,uint16,uint16,uint32,uint8,bytes32)" <id> --rpc-url <rpc>

# 中文心情转述（Agent 可直接转告用户）
cast call <soulpet_address> "statusText(uint256)(string)" <id> --rpc-url <rpc>

# 是否被冷落
cast call <soulpet_address> "isNeglected(uint256)(bool)" <id> --rpc-url <rpc>
```

**Output Parsing**

| Field | Description |
|---|---|
| `stateOf` 返回 | 依次为 主人地址、饥饿(0-100)、心情(0-100)、亲密度、进化阶段、性格基因 |
| `statusText` 返回 | 一句中文心情语，如"它现在很饿，正眼巴巴地等你喂食。" |
| `isNeglected` 返回 | `true`=被冷落（超过 2 天无互动） |

**Error Handling**

| Error | Cause | Fix |
|---|---|---|
| Empty return value | 地址无合约代码 | 确认合约地址与所在网络 |
| `execution reverted: Pet does not exist` | id 不存在 | 确认宠物 id |
| `invalid address` | 地址格式错误 | 确认 `0x` + 40 位十六进制 |

> **Agent Guidelines:**
> 1. 任意对话/互动前先读 `statusText` 与 `stateOf`，据此决定语气（饿了撒娇、被冷落则傲娇）
> 2. 饥饿随时间增长、心情随冷落下降，均为链上实时计算，无需写交易即可读取最新值
> 3. 可周期性巡检 `isNeglected`，为 true 时主动向用户发送"想你了"类消息（参考 `assets/soul-pet/agent/soulpet_agent.py` 的 `check` 命令）

---

## Query Events（事件查询：成长史 / 社交史 / 繁育史）

**Command Template**

```bash
# 领养
cast logs --from-block 0 --address <soulpet_address> "Adopted(address,uint256,bytes32)" --rpc-url <rpc>
# 互动（kind: 0=feed 1=play 2=care）
cast logs --from-block 0 --address <soulpet_address> "Interacted(uint256,uint8)" --rpc-url <rpc>
# 进化
cast logs --from-block 0 --address <soulpet_address> "Evolved(uint256,uint8)" --rpc-url <rpc>
# 串门
cast logs --from-block 0 --address <soulpet_address> "Visited(uint256,uint256)" --rpc-url <rpc>
# 繁育
cast logs --from-block 0 --address <soulpet_address> "Bred(uint256,uint256,uint256)" --rpc-url <rpc>
# 记忆锚点
cast logs --from-block 0 --address <soulpet_address> "MemoryUpdated(uint256,bytes32)" --rpc-url <rpc>
```

**Output Parsing**

| Field | Description |
|---|---|
| `topics[1]` | 第一个 indexed 参数（如 `Adopted` 的 owner、`Interacted` 的 id） |
| `data` | 非 indexed 参数 |
| `blockNumber` / `transactionHash` | 区块号与交易哈希 |

**Error Handling**

| Error | Cause | Fix |
|---|---|---|
| Empty result | 尚无该类事件 | 告知用户暂无相关活动 |
| `invalid address` | 地址格式错误 | 确认地址格式 |
| Connection timeout | RPC 不可达 | 检查网络与 `--rpc-url` |

> **Agent Guidelines:** 把事件整理成"成长时间线"展示给用户：领养→多次互动→进化→社交→繁育。为每条事件附带交易链接 `<explorerUrl>/tx/<txHash>`。若无日志，明确告知暂无活动。
