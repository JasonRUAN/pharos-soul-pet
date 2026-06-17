#!/usr/bin/env bash
#
# 将 SoulPet 合约部署到本地测试网络（anvil）
#
# 用法：
#   ./deploy.sh
#
# 前置条件：
#   1. 已安装 Foundry（forge / cast / anvil）
#   2. 已在另一个终端启动本地节点： anvil
#   3. 已配置 .env 文件（PRIVATE_KEY / RPC）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---- 加载环境变量 ----
if [[ ! -f .env ]]; then
  echo "错误：未找到 .env 文件，请先创建并填写 PRIVATE_KEY / RPC" >&2
  exit 1
fi

# 导出 .env 中的变量（自动 export）
set -a
# shellcheck disable=SC1091
source .env
set +a

# ---- 基本校验 ----
if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "错误：.env 中未设置 PRIVATE_KEY" >&2
  exit 1
fi

if [[ -z "${RPC:-}" ]]; then
  echo "错误：.env 中未设置 RPC" >&2
  exit 1
fi

echo "=== 部署配置 ==="
echo "RPC      : $RPC"
echo "Deployer : $DEPLOYER"
echo "================="

# ---- 检查本地节点是否可达 ----
if ! cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
  echo "错误：无法连接到 RPC ($RPC)，请先在另一终端运行 'anvil'" >&2
  exit 1
fi

# ---- 编译 ----
echo "编译合约..."
forge build

# ---- 部署 ----
echo "部署 SoulPet 到本地网络..."
forge script script/DeploySoulPet.s.sol:DeploySoulPet \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv

echo "部署完成。"
