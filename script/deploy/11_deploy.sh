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

# 被依赖方地址必须在广播前校验为已部署合约，避免白广播本库 13 个合约。
# MemberNFT/Phase/LOVE20Token/Submit/Vote/Stake/Launch 来自 core；ActionTarget/GroupActionExecutor 来自 action。
require_dependency_addresses() {
    local field
    for field in MEMBER_NFT_ADDRESS PHASE_ADDRESS LOVE20_TOKEN_ADDRESS \
        SUBMIT_ADDRESS VOTE_ADDRESS STAKE_ADDRESS LAUNCH_ADDRESS; do
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

    local love20_address
    if ! love20_address=$(cast call "$MEMBER_NFT_ADDRESS" "LOVE20_TOKEN_ADDRESS()(address)" --rpc-url "$RPC_URL" 2>/dev/null); then
        echo "Error: Failed to read MemberNFT.LOVE20_TOKEN_ADDRESS from $MEMBER_NFT_ADDRESS"
        exit 1
    fi
    require_contract_code "MemberNFT.LOVE20_TOKEN_ADDRESS" "$love20_address"
    require_same_address "MemberNFT.LOVE20_TOKEN_ADDRESS" "$love20_address" "$LOVE20_TOKEN_ADDRESS"

    local action_target_member_nft action_target_phase
    if ! action_target_member_nft=$(cast call "$ACTION_TARGET_ADDRESS" "memberNFTAddress()(address)" --rpc-url "$RPC_URL" 2>/dev/null); then
        echo "Error: Failed to read ActionTarget.memberNFTAddress from $ACTION_TARGET_ADDRESS"
        exit 1
    fi
    if ! action_target_phase=$(cast call "$ACTION_TARGET_ADDRESS" "phaseAddress()(address)" --rpc-url "$RPC_URL" 2>/dev/null); then
        echo "Error: Failed to read ActionTarget.phaseAddress from $ACTION_TARGET_ADDRESS"
        exit 1
    fi
    require_same_address "ActionTarget.memberNFTAddress" "$action_target_member_nft" "$MEMBER_NFT_ADDRESS"
    require_same_address "ActionTarget.phaseAddress" "$action_target_phase" "$PHASE_ADDRESS"

    local phase_origin_blocks
    if ! phase_origin_blocks=$(cast call "$PHASE_ADDRESS" "ORIGIN_PHASE_BLOCKS()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null); then
        echo "Error: Failed to read Phase.ORIGIN_PHASE_BLOCKS from $PHASE_ADDRESS"
        exit 1
    fi
    phase_origin_blocks=$(echo "$phase_origin_blocks" | sed -E 's/\[[0-9.]+e[0-9]+\]//g' | tr -d ' ')
    if [[ ! "$phase_origin_blocks" =~ ^[0-9]+$ ]] || [ "$phase_origin_blocks" -eq 0 ]; then
        echo "Error: Phase.ORIGIN_PHASE_BLOCKS must be > 0 (current: ${phase_origin_blocks:-unknown})"
        exit 1
    fi
}

require_contract_code() {
    local name="$1" address="$2" code
    if [[ ! "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ "$address" = 0x0000000000000000000000000000000000000000 ]]; then
        echo "Error: $name is missing or invalid ($address)"
        exit 1
    fi
    if ! code=$(cast code "$address" --rpc-url "$RPC_URL" 2>/dev/null) \
        || [[ ! "$code" =~ ^0x[0-9a-fA-F]+$ ]] || [[ "$code" = "0x" ]]; then
        echo "Error: $name $address is not a deployed contract on chain $CHAIN_ID"
        exit 1
    fi
}

require_same_address() {
    local name="$1" actual="$2" expected="$3"
    if [ "$(echo "$actual" | tr '[:upper:]' '[:lower:]')" \
        != "$(echo "$expected" | tr '[:upper:]' '[:lower:]')" ]; then
        echo "Error: $name ($actual) does not match core params ($expected)"
        exit 1
    fi
}

require_optional_contract_code() {
    local name="$1" address="${2:-}"
    if [ -z "$address" ] || [ "$address" = "0x0000000000000000000000000000000000000000" ]; then
        return 0
    fi
    require_contract_code "$name" "$address"
}

# Manager 从 ActionTarget/Vote/Stake 派生的地址：必须在广播前有代码且与 core 地址文件一致。
require_derived_dependency_addresses() {
    local submit vote stake launch
    submit=$(cast call "$ACTION_TARGET_ADDRESS" "submitAddress()(address)" --rpc-url "$RPC_URL") \
        || { echo "Error: Failed to read ActionTarget.submitAddress"; exit 1; }
    vote=$(cast call "$ACTION_TARGET_ADDRESS" "voteAddress()(address)" --rpc-url "$RPC_URL") \
        || { echo "Error: Failed to read ActionTarget.voteAddress"; exit 1; }
    stake=$(cast call "$vote" "stakeAddress()(address)" --rpc-url "$RPC_URL") \
        || { echo "Error: Failed to read Vote.stakeAddress"; exit 1; }
    launch=$(cast call "$stake" "launchAddress()(address)" --rpc-url "$RPC_URL") \
        || { echo "Error: Failed to read Stake.launchAddress"; exit 1; }

    require_contract_code "ActionTarget.submitAddress" "$submit"
    require_contract_code "ActionTarget.voteAddress" "$vote"
    require_contract_code "Vote.stakeAddress" "$stake"
    require_contract_code "Stake.launchAddress" "$launch"

    require_same_address "ActionTarget.submitAddress" "$submit" "$SUBMIT_ADDRESS"
    require_same_address "ActionTarget.voteAddress" "$vote" "$VOTE_ADDRESS"
    require_same_address "Vote.stakeAddress" "$stake" "$STAKE_ADDRESS"
    require_same_address "Stake.launchAddress" "$launch" "$LAUNCH_ADDRESS"
}

# 当前四个 Manager 的类型码都是 2 字节；名称空间下限 = typeCode.length + 9 = 11。
# 新增更长类型码时同步调整本处、DeployGroupChat.s.sol 与 21_check.sh。
# 合约不再自检，部署前在这里拦截坏配置。
require_member_name_space() {
    local max_name_length min_name_length=11
    if ! max_name_length=$(cast call "$MEMBER_NFT_ADDRESS" "MAX_NAME_LENGTH()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null); then
        echo "Error: Failed to read MemberNFT.MAX_NAME_LENGTH from $MEMBER_NFT_ADDRESS"
        exit 1
    fi
    max_name_length=$(echo "$max_name_length" | sed -E 's/\[[0-9.]+e[0-9]+\]//g' | tr -d ' ')
    if [[ ! "$max_name_length" =~ ^[0-9]+$ ]] || [ "$max_name_length" -lt "$min_name_length" ]; then
        echo "Error: MemberNFT.MAX_NAME_LENGTH must be >= $min_name_length (current: ${max_name_length:-unknown}); managers use 2-byte type codes."
        exit 1
    fi
}

# group-chat.params 的构造参数：零值会让部署出来的合约不可用，缺项即失败。
# BAN_THRESHOLD_RATIO 允许 0（旧构造只限制上界），只要求为整数且 <= 1e18。
require_group_chat_params() {
    local field value
    for field in GROUP_CHAT_ACTION_RECENT_ROUNDS GROUP_CHAT_MAX_CONTENT_LENGTH \
        GROUP_CHAT_MAX_MENTIONED_SENDER_IDS GROUP_CHAT_MAX_ADMIN_IDS \
        GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER; do
        value="${!field:-}"
        if [ -z "$value" ] || [[ ! "$value" =~ ^[0-9]+$ ]] || [ "$value" -eq 0 ]; then
            echo "Error: $field must be a positive integer in $NETWORK_DIR/group-chat.params"
            exit 1
        fi
    done
    if [[ ! "${GROUP_CHAT_BAN_THRESHOLD_RATIO:-}" =~ ^[0-9]+$ ]] \
        || [ "$GROUP_CHAT_BAN_THRESHOLD_RATIO" -gt 1000000000000000000 ]; then
        echo "Error: GROUP_CHAT_BAN_THRESHOLD_RATIO must be an integer <= 1e18 in $NETWORK_DIR/group-chat.params"
        exit 1
    fi
    require_optional_contract_code "GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS" \
        "${GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS:-0x0000000000000000000000000000000000000000}"
    require_optional_contract_code "GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS" \
        "${GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS:-0x0000000000000000000000000000000000000000}"
}

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

require_dependency_addresses
require_derived_dependency_addresses
require_member_name_space
require_group_chat_params

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
