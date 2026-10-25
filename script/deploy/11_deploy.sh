#!/usr/bin/env bash
set -euo pipefail

# 步骤一：合约部署与初始化。自包含——自行加载并校验部署所需文件，不依赖调用方预载环境。
# 用法：script/deploy/11_deploy.sh <network>
# 部署产物 addresses.group-chat.params 由本步骤写入，供 21_check.sh 与 31_verify.sh 自行载入。

network="${1:?usage: script/deploy/11_deploy.sh <network>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NETWORK_DIR="$PROJECT_ROOT/script/network/$network"

if [ ! -d "$NETWORK_DIR" ]; then
    echo "Error: Network directory not found: $NETWORK_DIR"
    exit 1
fi

# 上一次异常退出可能留下地址临时文件；只清理本模块的隐藏临时模式，不碰正式地址文件。
rm -f "$NETWORK_DIR/.addresses.group-chat.params."*

# 必需配置：addresses.core.params / addresses.action.params 是被依赖方已部署地址，按依赖顺序 source。
for config in network.params addresses.core.params addresses.action.params group-chat.params .account; do
    if [ ! -f "$NETWORK_DIR/$config" ]; then
        echo "Error: Missing required configuration: $NETWORK_DIR/$config"
        exit 1
    fi
done

env_password="${KEYSTORE_PASSWORD:-}"
set -a
source "$NETWORK_DIR/network.params"
source "$NETWORK_DIR/addresses.core.params"
source "$NETWORK_DIR/addresses.action.params"
source "$NETWORK_DIR/group-chat.params"
source "$NETWORK_DIR/.account"
set +a

# 可选插件空值统一按零地址处理，避免 shell 跳过校验而 forge 解析空字符串失败。
GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS="${GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS:-0x0000000000000000000000000000000000000000}"
GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS="${GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS:-0x0000000000000000000000000000000000000000}"
export GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS

# .account 里的空 KEYSTORE_PASSWORD 行不应清掉入口已导出的密码（避免重复弹窗）。
[ -n "${KEYSTORE_PASSWORD:-}" ] || KEYSTORE_PASSWORD="$env_password"

[ -n "${KEYSTORE_ACCOUNT:-}" ] && [ -n "${ACCOUNT_ADDRESS:-}" ] \
    || { echo "Error: KEYSTORE_ACCOUNT / ACCOUNT_ADDRESS is not set in $NETWORK_DIR/.account" >&2; exit 1; }

# 确认实际链，不能只检查 RPC 是否可连接。
ACTUAL_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL") || exit 1
if [ "$ACTUAL_CHAIN_ID" != "$CHAIN_ID" ]; then
    echo "Error: RPC chain ID $ACTUAL_CHAIN_ID does not match configured CHAIN_ID $CHAIN_ID"
    exit 1
fi

# keystore 密码：已设则不弹窗（非交互调用用）；留空则 macOS 弹窗读取。
if [ -z "${KEYSTORE_PASSWORD:-}" ]; then
    if ! command -v osascript >/dev/null 2>&1; then
        echo "Error: KEYSTORE_PASSWORD is empty and osascript is unavailable; set it in $NETWORK_DIR/.account for non-interactive use." >&2
        exit 1
    fi
    KEYSTORE_PASSWORD="$(osascript <<APPLESCRIPT
text returned of (display dialog "Enter keystore password for $KEYSTORE_ACCOUNT:" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK")
APPLESCRIPT
)"
fi

# 13 个合约地址：从部署日志提取后逐项校验，缺项即失败，不写半截地址文件。
require_deployed_addresses() {
    local field
    for field in GROUP_CHAT_DELEGATE_ADDRESS GROUP_ADMIN_ADDRESS GROUP_CHAT_ADDRESS \
        GROUP_CHAT_BAN_LIST_ADDRESS ADMIN_BAN_SOURCE_ADDRESS GOV_VOTED_BAN_SOURCE_ADDRESS \
        GROUP_MEMBER_ADDRESS GROUP_MEMBER_SCOPE_ADDRESS GROUP_JOIN_SCOPE_SOURCE_ADDRESS \
        TOKEN_MAIN_MANAGER_ADDRESS TOKEN_GOV_MANAGER_ADDRESS TOKEN_ACTION_GOV_MANAGER_ADDRESS \
        TOKEN_ACTION_MAIN_MANAGER_ADDRESS; do
        if [[ ! ${!field:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ ${!field:-} = 0x0000000000000000000000000000000000000000 ]]; then
            echo "Error: Missing or invalid $field extracted from deployment log"
            exit 1
        fi
    done
}

echo "=== Deploying GroupChat Contracts to $network ==="
echo "  RPC_URL: $RPC_URL"
echo "  CHAIN_ID: $CHAIN_ID"

# 广播后失败必须留下日志与产物路径供人工恢复；广播前失败只清理本次临时文件。
# 密码经临时文件传给 forge：--password 会把明文放进进程参数（/proc/<pid>/cmdline 权限 0444，
# 本机所有用户可读）。trap 在写入密码之前安装，chmod/printf 失败也不会留下明文。
DEPLOY_LOG=$(mktemp)
PASSWORD_FILE=$(mktemp)
ADDRESS_TMP="$NETWORK_DIR/.addresses.group-chat.params.$$"
DEPLOY_SAVED=0
DEPLOY_ATTEMPTED=0
trap 'rm -f "$ADDRESS_TMP" "$PASSWORD_FILE"
if [ "$DEPLOY_SAVED" = 1 ] || [ "$DEPLOY_ATTEMPTED" = 0 ]; then
    rm -f "$DEPLOY_LOG"
else
    echo "  Addresses were not saved; contracts may already be on chain." >&2
    echo "  Deployment log: $DEPLOY_LOG" >&2
    echo "  Broadcast artifact: $PROJECT_ROOT/broadcast/DeployGroupChat.s.sol/${CHAIN_ID:-unknown}/run-latest.json" >&2
fi' EXIT
chmod 600 "$PASSWORD_FILE"
printf '%s' "$KEYSTORE_PASSWORD" > "$PASSWORD_FILE"

cd "$PROJECT_ROOT"
DEPLOY_START_EPOCH_SECONDS=$(date +%s)
DEPLOY_ATTEMPTED=1
if ! { forge script script/deploy/DeployGroupChat.s.sol:DeployGroupChat \
    --sig "run()" \
    --rpc-url "$RPC_URL" \
    --chain-id "$CHAIN_ID" \
    --account "$KEYSTORE_ACCOUNT" \
    --sender "$ACCOUNT_ADDRESS" \
    --password-file "$PASSWORD_FILE" \
    --broadcast --slow -vvv 2>&1 | tee "$DEPLOY_LOG"; }; then
    echo "Error: Deployment failed; saved addresses were not changed."
    exit 1
fi
# 密码只在本次 forge 调用期间需要，广播结束立即删除。
rm -f "$PASSWORD_FILE"

# 从部署输出中提取地址（DeployGroupChat.s.sol 的 _logDeploymentSummary 输出）。
# grep 无匹配会让管道在 set -e 下静默中止，故逐个容错取值，缺项交由 require_deployed_addresses 报错。
for field in GROUP_CHAT_DELEGATE_ADDRESS GROUP_ADMIN_ADDRESS GROUP_CHAT_ADDRESS \
    GROUP_CHAT_BAN_LIST_ADDRESS ADMIN_BAN_SOURCE_ADDRESS GOV_VOTED_BAN_SOURCE_ADDRESS \
    GROUP_MEMBER_ADDRESS GROUP_MEMBER_SCOPE_ADDRESS GROUP_JOIN_SCOPE_SOURCE_ADDRESS \
    TOKEN_MAIN_MANAGER_ADDRESS TOKEN_GOV_MANAGER_ADDRESS TOKEN_ACTION_GOV_MANAGER_ADDRESS \
    TOKEN_ACTION_MAIN_MANAGER_ADDRESS; do
    eval "$field=\$(grep \"$field=\" \"\$DEPLOY_LOG\" | tail -1 | cut -d'=' -f2 | xargs || true)"
done

require_deployed_addresses

BROADCAST_FILE="$PROJECT_ROOT/broadcast/DeployGroupChat.s.sol/$CHAIN_ID/run-latest.json"
if [ ! -f "$BROADCAST_FILE" ]; then
    echo "Error: Missing broadcast artifact: $BROADCAST_FILE"
    exit 1
fi
BROADCAST_TIMESTAMP_MS=$(sed -nE 's/.*"timestamp":[[:space:]]*([0-9]+).*/\1/p' "$BROADCAST_FILE" | tail -1)
if [ -z "$BROADCAST_TIMESTAMP_MS" ] || [ "$BROADCAST_TIMESTAMP_MS" -lt "$((DEPLOY_START_EPOCH_SECONDS * 1000))" ]; then
    echo "Error: Broadcast artifact was not updated by this deployment: $BROADCAST_FILE"
    exit 1
fi

cat > "$ADDRESS_TMP" <<EOFADDR
# group-chat 已部署地址，由 script/deploy/11_deploy.sh 写入；勿手改。
GROUP_CHAT_DELEGATE_ADDRESS=$GROUP_CHAT_DELEGATE_ADDRESS
GROUP_ADMIN_ADDRESS=$GROUP_ADMIN_ADDRESS
GROUP_CHAT_ADDRESS=$GROUP_CHAT_ADDRESS
GROUP_CHAT_BAN_LIST_ADDRESS=$GROUP_CHAT_BAN_LIST_ADDRESS
ADMIN_BAN_SOURCE_ADDRESS=$ADMIN_BAN_SOURCE_ADDRESS
GOV_VOTED_BAN_SOURCE_ADDRESS=$GOV_VOTED_BAN_SOURCE_ADDRESS
GROUP_MEMBER_ADDRESS=$GROUP_MEMBER_ADDRESS
GROUP_MEMBER_SCOPE_ADDRESS=$GROUP_MEMBER_SCOPE_ADDRESS
GROUP_JOIN_SCOPE_SOURCE_ADDRESS=$GROUP_JOIN_SCOPE_SOURCE_ADDRESS
TOKEN_MAIN_MANAGER_ADDRESS=$TOKEN_MAIN_MANAGER_ADDRESS
TOKEN_GOV_MANAGER_ADDRESS=$TOKEN_GOV_MANAGER_ADDRESS
TOKEN_ACTION_GOV_MANAGER_ADDRESS=$TOKEN_ACTION_GOV_MANAGER_ADDRESS
TOKEN_ACTION_MAIN_MANAGER_ADDRESS=$TOKEN_ACTION_MAIN_MANAGER_ADDRESS
EOFADDR
mv "$ADDRESS_TMP" "$NETWORK_DIR/addresses.group-chat.params"

DEPLOY_SAVED=1
echo "✓ Deployment completed and addresses saved to $NETWORK_DIR/addresses.group-chat.params"
