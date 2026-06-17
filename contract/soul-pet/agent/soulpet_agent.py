#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SoulPet 附身 Agent —— 情绪驱动的链上 AI 伴侣演示脚本

设计目标（对应 04-SoulPet.md 的 Phase 2）：
  1. 主人发指令时，Agent 先读取链上 stateOf / statusText 感知宠物情绪；
  2. 据此用"人格化"的中文语气回应（饿了撒娇要吃、被冷落则傲娇）；
  3. 互动产生链上状态变更（feed / play / care / visit）；
  4. 后台巡检 isNeglected，主动发"想你了"。

实现说明：
  - 零第三方依赖，仅用 Python 标准库 subprocess 调用 Foundry 的 `cast`；
  - 人格/语气完全由链上状态 + 性格基因（traits）规则化推导，自包含、可离线演示；
  - 如需接入大语言模型生成更自然的对话，可在 _voice() 处把规则文本作为 system 提示词喂给 LLM。

环境变量：
  - RPC             ：Pharos RPC 地址（默认 Atlantic 测试网）
  - SOULPET_ADDRESS ：已部署的 SoulPet 合约地址
  - PRIVATE_KEY     ：主人私钥（仅写操作需要）

用法示例：
  python soulpet_agent.py adopt 0x01
  python soulpet_agent.py status 1
  python soulpet_agent.py feed 1
  python soulpet_agent.py play 1
  python soulpet_agent.py care 1
  python soulpet_agent.py visit 1 2
  python soulpet_agent.py check 1
"""

import os
import subprocess
import sys

# Atlantic 测试网默认 RPC
DEFAULT_RPC = "https://atlantic.dplabs-internal.com"


def _env(name, default=None, required=False):
    """读取环境变量，required=True 时缺失会报错退出。"""
    val = os.environ.get(name, default)
    if required and not val:
        sys.exit(f"[错误] 环境变量 {name} 未设置，请先 export {name}=...")
    return val


def _run_cast(args):
    """运行一条 cast 命令并返回标准输出（已 strip）。出错时打印 stderr 并退出。"""
    cmd = ["cast"] + args
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except FileNotFoundError:
        sys.exit("[错误] 未找到 cast，请先安装 Foundry：curl -L https://foundry.paradigm.xyz | bash && foundryup")
    except subprocess.CalledProcessError as e:
        # 把链上 revert 原因等错误转述给用户
        sys.exit(f"[链上错误] {e.stderr.strip() or e.stdout.strip()}")
    return out.stdout.strip()


def _addr():
    return _env("SOULPET_ADDRESS", required=True)


def _rpc():
    return _env("RPC", DEFAULT_RPC)


# ---------------------------------------------------------------------------
# 链上读取
# ---------------------------------------------------------------------------

def read_state(pet_id):
    """读取宠物的实时数值状态，返回 dict。"""
    raw = _run_cast([
        "call", _addr(),
        "stateOf(uint256)(address,uint16,uint16,uint32,uint8,bytes32)",
        str(pet_id), "--rpc-url", _rpc(),
    ])
    # cast 多返回值以换行分隔
    lines = [l.strip() for l in raw.splitlines() if l.strip()]
    return {
        "owner": lines[0],
        "hunger": int(lines[1].split()[0]),
        "mood": int(lines[2].split()[0]),
        "affinity": int(lines[3].split()[0]),
        "stage": int(lines[4].split()[0]),
        "traits": lines[5],
    }


def read_status_text(pet_id):
    """读取合约内置的中文状态语。"""
    raw = _run_cast([
        "call", _addr(), "statusText(uint256)(string)",
        str(pet_id), "--rpc-url", _rpc(),
    ])
    return raw.strip().strip('"')


def is_neglected(pet_id):
    raw = _run_cast([
        "call", _addr(), "isNeglected(uint256)(bool)",
        str(pet_id), "--rpc-url", _rpc(),
    ])
    return raw.strip().lower() == "true"


# ---------------------------------------------------------------------------
# 人格引擎：把链上状态 + 性格基因 → 中文语气
# ---------------------------------------------------------------------------

# 用性格基因的首字节决定人格原型
PERSONAS = ["傲娇", "黏人", "慵懒", "活泼"]


def _persona_of(traits_hex):
    """根据 traits（bytes32 十六进制）推导人格原型。"""
    try:
        first_byte = int(traits_hex[2:4], 16) if traits_hex.startswith("0x") else 0
    except ValueError:
        first_byte = 0
    return PERSONAS[first_byte % len(PERSONAS)]


def _voice(state, neglected):
    """根据状态与人格生成一句宠物口吻的中文台词。"""
    persona = _persona_of(state["traits"])
    hunger, mood, affinity = state["hunger"], state["mood"], state["affinity"]

    if neglected:
        lines = {
            "傲娇": "哼，你终于想起我了？我才没有等你呢……（小声）其实等了好久。",
            "黏人": "你去哪儿了呀，我好想你！别再丢下我了好不好～",
            "慵懒": "（揉眼睛）你回来啦……我都快睡过去了，陪陪我嘛。",
            "活泼": "终于等到你！我都憋坏啦，快陪我玩！",
        }
        return lines[persona]

    if hunger >= 70:
        lines = {
            "傲娇": "我、我才不是饿了呢……不过你要喂的话，我勉为其难吃一点。",
            "黏人": "肚子咕咕叫啦，主人喂喂我嘛～",
            "慵懒": "好饿……懒得动，你喂我好不好。",
            "活泼": "饿饿饿！快给我吃的，吃饱了陪你疯一整天！",
        }
        return lines[persona]

    if mood >= 70:
        return {
            "傲娇": "今天心情还……还不错啦，都是托你的福（脸红）。",
            "黏人": "和你在一起最开心啦，要一直一直在一起哦！",
            "慵懒": "晒着太阳，旁边有你，这样的日子真舒服。",
            "活泼": "我超开心的！我们再玩一局好不好好不好！",
        }[persona]

    if mood <= 30:
        return {
            "傲娇": "……今天有点提不起劲，但才不是想让你哄我呢。",
            "黏人": "我有点难过，可以抱抱我吗……",
            "慵懒": "没什么精神……陪我安静待会儿就好。",
            "活泼": "唔，今天蔫蔫的，陪我动一动也许会好点。",
        }[persona]

    closeness = "（和你已经很亲密啦）" if affinity >= 100 else ""
    return {
        "傲娇": f"还行吧，凑合过得去。{closeness}",
        "黏人": f"在你身边就很安心～{closeness}",
        "慵懒": f"平平淡淡的一天，挺好。{closeness}",
        "活泼": f"精神不错，随时可以出发！{closeness}",
    }[persona]


def _pretty(state):
    persona = _persona_of(state["traits"])
    return (f"[宠物 #链上状态] 人格={persona} 阶段={state['stage']} "
            f"饥饿={state['hunger']} 心情={state['mood']} 亲密度={state['affinity']}")


# ---------------------------------------------------------------------------
# 写操作（需要私钥）
# ---------------------------------------------------------------------------

def _send(method, *call_args, value=None):
    pk = _env("PRIVATE_KEY", required=True)
    args = ["send", _addr(), method, *[str(a) for a in call_args],
            "--private-key", pk, "--rpc-url", _rpc()]
    if value:
        args += ["--value", value]
    return _run_cast(args)


# ---------------------------------------------------------------------------
# 命令处理
# ---------------------------------------------------------------------------

def cmd_status(pet_id):
    state = read_state(pet_id)
    print(_pretty(state))
    print("链上转述：", read_status_text(pet_id))
    print("宠物说：", _voice(state, is_neglected(pet_id)))


def cmd_feed(pet_id):
    print("正在喂食……")
    _send("feed(uint256)", pet_id)
    state = read_state(pet_id)
    print(_pretty(state))
    print("宠物说：", _voice(state, False))


def cmd_play(pet_id):
    print("正在陪玩……")
    _send("play(uint256)", pet_id)
    state = read_state(pet_id)
    print(_pretty(state))
    print("宠物说：", _voice(state, False))


def cmd_care(pet_id):
    print("正在照料……")
    _send("care(uint256)", pet_id)
    state = read_state(pet_id)
    print(_pretty(state))
    print("宠物说：", _voice(state, False))


def cmd_visit(pet_id, other_id):
    print(f"带 #{pet_id} 去拜访 #{other_id}……")
    _send("visit(uint256,uint256)", pet_id, other_id)
    print("两只宠物都更开心啦，主人之间也因此连接 ~")
    cmd_status(pet_id)


def cmd_adopt(traits_hex):
    print("正在领养一只新的 SoulPet……")
    # bytes32 需补齐到 32 字节
    if traits_hex.startswith("0x"):
        traits_hex = traits_hex[2:]
    traits = "0x" + traits_hex.rjust(64, "0")
    _send("adopt(bytes32)", traits)
    print("领养成功！用 `status <id>` 查看它的状态吧。")


def cmd_check(pet_id):
    """后台巡检：被冷落时生成一条主动陪伴消息。"""
    if is_neglected(pet_id):
        state = read_state(pet_id)
        print("【主动消息】", _voice(state, True))
    else:
        print("宠物状态良好，暂不需要主动打扰。")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    rest = sys.argv[2:]

    handlers = {
        "status": (cmd_status, 1),
        "feed": (cmd_feed, 1),
        "play": (cmd_play, 1),
        "care": (cmd_care, 1),
        "visit": (cmd_visit, 2),
        "adopt": (cmd_adopt, 1),
        "check": (cmd_check, 1),
    }

    if cmd not in handlers:
        sys.exit(f"[错误] 未知命令：{cmd}\n{__doc__}")

    handler, argc = handlers[cmd]
    if len(rest) != argc:
        sys.exit(f"[错误] 命令 {cmd} 需要 {argc} 个参数，收到 {len(rest)} 个。")

    handler(*rest)


if __name__ == "__main__":
    main()
