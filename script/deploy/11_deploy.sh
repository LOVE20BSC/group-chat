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

# 被依赖方地址必须在广播前校验为已部署合约，避免白广播本库 13 个合约。
# MemberNFT 与 Phase 来自 core；ActionTarget 与 GroupActionExecutor 来自 action。
require_dependency_addresses() {
    local field
    for field in GROUP_ADDRESS PHASE_ADDRESS; do
        if [[ ! ${!field:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ ${!field:-} = 0x0000000000000000000000000000000000000000 ]]; then
            echo "Error: Missing or invalid $field in $NETWORK_DIR/addresses.core.params"
            exit 1
        fi
        local code
        if ! code=$(cast code "${!field}" --rpc-url "$RPC_URL" 2>/dev/null) || [[ ! "$code" =~ ^0x[0-9a-fA-F]+$ ]]; then
            echo "Error: $field ${!field} is not a deployed contract on chain $CHAIN_ID"
            exit 1
        fi
    done
    for field in ACTION_TARGET_ADDRESS GROUP_ACTION_EXECUTOR_ADDRESS; do
        if [[ ! ${!field:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ ${!field:-} = 0x0000000000000000000000000000000000000000 ]]; then
            echo "Error: Missing or invalid $field in $NETWORK_DIR/addresses.action.params"
            exit 1
        fi
        if ! code=$(cast code "${!field}" --rpc-url "$RPC_URL" 2>/dev/null) || [[ ! "$code" =~ ^0x[0-9a-fA-F]+$ ]]; then
            echo "Error: $field ${!field} is not a deployed contract on chain $CHAIN_ID"
            exit 1
        fi
    done
}

# group-chat.params 的构造参数：零值会让部署出来的合约不可用，缺项即失败。
require_group_chat_params() {
    local field
    for field in GROUP_CHAT_ACTION_RECENT_ROUNDS GROUP_CHAT_MAX_CONTENT_LENGTH \
        GROUP_CHAT_MAX_MENTIONED_SENDER_IDS GROUP_CHAT_MAX_ADMIN_IDS \
        GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER GROUP_CHAT_BAN_THRESHOLD_RATIO; do
        if [ -z "${!field:-}" ] || [ "${!field}" = "0" ]; then
            echo "Error: $field is missing or zero in $NETWORK_DIR/group-chat.params"
            exit 1
        fi
    done
}

# 13 个合约地址：从部署日志提取后逐项校验，缺项即失败，不写半截地址文件。
require_deployed_addresses() {
    local field
    for field in GROUPCHATDELEGATE_ADDRESS GROUPADMIN_ADDRESS GROUPCHAT_ADDRESS \
        GROUPCHATBANLIST_ADDRESS ADMINBANSOURCE_ADDRESS GOVVOTEDBANSOURCE_ADDRESS \
        GROUPMEMBER_ADDRESS GROUPMEMBERSCOPE_ADDRESS GROUPJOINSCOPESOURCE_ADDRESS \
        TOKENMAINMANAGER_ADDRESS TOKENGOVMANAGER_ADDRESS TOKENACTIONGOVMANAGER_ADDRESS \
        TOKENACTIONMAINMANAGER_ADDRESS; do
        if [[ ! ${!field:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ ${!field:-} = 0x0000000000000000000000000000000000000000 ]]; then
            echo "Error: Missing or invalid $field extracted from deployment log"
            exit 1
        fi
    done
}

echo "=== Deploying GroupChat Contracts to $network ==="
echo "  RPC_URL: $RPC_URL"
echo "  CHAIN_ID: $CHAIN_ID"

require_dependency_addresses
require_group_chat_params

DEPLOY_LOG=$(mktemp)
trap "rm -f $DEPLOY_LOG" EXIT

cd "$PROJECT_ROOT"
if ! { forge script script/deploy/DeployGroupChat.s.sol:DeployGroupChat \
    --sig "run()" \
    --rpc-url "$RPC_URL" \
    --chain-id "$CHAIN_ID" \
    --account "$KEYSTORE_ACCOUNT" \
    --sender "$ACCOUNT_ADDRESS" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast --slow -vvv 2>&1 | tee "$DEPLOY_LOG"; }; then
    echo "Error: Deployment failed; saved addresses were not changed."
    exit 1
fi

# 从部署输出中提取地址（DeployGroupChat.s.sol 的 _logDeploymentSummary 输出）。
# grep 无匹配会让管道在 set -e 下静默中止，故逐个容错取值，缺项交由 require_deployed_addresses 报错。
for field in GROUPCHATDELEGATE_ADDRESS GROUPADMIN_ADDRESS GROUPCHAT_ADDRESS \
    GROUPCHATBANLIST_ADDRESS ADMINBANSOURCE_ADDRESS GOVVOTEDBANSOURCE_ADDRESS \
    GROUPMEMBER_ADDRESS GROUPMEMBERSCOPE_ADDRESS GROUPJOINSCOPESOURCE_ADDRESS \
    TOKENMAINMANAGER_ADDRESS TOKENGOVMANAGER_ADDRESS TOKENACTIONGOVMANAGER_ADDRESS \
    TOKENACTIONMAINMANAGER_ADDRESS; do
    eval "$field=\$(grep \"$field=\" \"\$DEPLOY_LOG\" | tail -1 | cut -d'=' -f2 | xargs || true)"
done

require_deployed_addresses

cat > "$NETWORK_DIR/addresses.group-chat.params" <<EOFADDR
# group-chat 已部署地址，由 script/deploy/11_deploy.sh 写入；勿手改。
GROUPCHATDELEGATE_ADDRESS=$GROUPCHATDELEGATE_ADDRESS
GROUPADMIN_ADDRESS=$GROUPADMIN_ADDRESS
GROUPCHAT_ADDRESS=$GROUPCHAT_ADDRESS
GROUPCHATBANLIST_ADDRESS=$GROUPCHATBANLIST_ADDRESS
ADMINBANSOURCE_ADDRESS=$ADMINBANSOURCE_ADDRESS
GOVVOTEDBANSOURCE_ADDRESS=$GOVVOTEDBANSOURCE_ADDRESS
GROUPMEMBER_ADDRESS=$GROUPMEMBER_ADDRESS
GROUPMEMBERSCOPE_ADDRESS=$GROUPMEMBERSCOPE_ADDRESS
GROUPJOINSCOPESOURCE_ADDRESS=$GROUPJOINSCOPESOURCE_ADDRESS
TOKENMAINMANAGER_ADDRESS=$TOKENMAINMANAGER_ADDRESS
TOKENGOVMANAGER_ADDRESS=$TOKENGOVMANAGER_ADDRESS
TOKENACTIONGOVMANAGER_ADDRESS=$TOKENACTIONGOVMANAGER_ADDRESS
TOKENACTIONMAINMANAGER_ADDRESS=$TOKENACTIONMAINMANAGER_ADDRESS
EOFADDR

echo "✓ Deployment completed and addresses saved to $NETWORK_DIR/addresses.group-chat.params"
