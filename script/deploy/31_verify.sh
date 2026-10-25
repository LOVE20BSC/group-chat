#!/usr/bin/env bash
set -euo pipefail

# 步骤三：合约开源验证。自包含——自行载入 network.params、被依赖方地址、构造参数与上次部署
# 写入的 addresses.group-chat.params，不依赖入口脚本在部署后刷新地址。
# 构造参数经 cast abi-encode 显式编码，不依赖 broadcast 产物的自动识别。
# 链未配置 verifier 时跳过并返回成功，不视为失败，使本地链也能一键跑通。
# 用法：script/deploy/31_verify.sh <network>

network="${1:?usage: script/deploy/31_verify.sh <network>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NETWORK_DIR="$PROJECT_ROOT/script/network/$network"

# 参数文件载入器：1e17 / 1_000_000 这类写法在载入时展开为十进制（见 params.sh）。
source "$SCRIPT_DIR/params.sh"

if [ ! -d "$NETWORK_DIR" ]; then
    echo "Error: Network directory not found: $NETWORK_DIR"
    exit 1
fi

for config in network.params addresses.core.params addresses.action.params group-chat.params addresses.group-chat.params; do
    if [ ! -f "$NETWORK_DIR/$config" ]; then
        echo "Error: Missing required configuration: $NETWORK_DIR/$config"
        exit 1
    fi
done

# 参数只来自文件：清掉调用方环境里可能残留的同名变量，否则缺键会被继承值掩盖。
unset GROUP_CHAT_ACTION_RECENT_ROUNDS GROUP_CHAT_MAX_CONTENT_LENGTH GROUP_CHAT_MAX_MENTIONED_SENDER_IDS \
    GROUP_CHAT_MAX_ADMIN_IDS GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER GROUP_CHAT_BAN_THRESHOLD_RATIO \
    GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS

params_load "$NETWORK_DIR/network.params"
params_load "$NETWORK_DIR/addresses.core.params"
params_load "$NETWORK_DIR/addresses.action.params"
params_load "$NETWORK_DIR/group-chat.params"
params_load "$NETWORK_DIR/addresses.group-chat.params"

# 插件槽位是必填键（零地址=未挂载）：缺键时不能按零地址编码构造参数，否则实参与部署不一致。
if [ -z "${GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS:-}" ] || [ -z "${GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS:-}" ]; then
    echo "Error: GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS / GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS must be set in $NETWORK_DIR/group-chat.params (use 0x0000000000000000000000000000000000000000 for no plugin)" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

# network.params 未提供 verifier 的链不适用例（本地 anvil、未接入浏览器的链），直接跳过。
if [ -z "${VERIFIER:-}" ] || [ -z "${VERIFIER_URL:-}" ]; then
    echo "Skip: source verification is not configured for chain $CHAIN_ID"
    exit 0
fi

# 13 个合约地址缺项即失败：forge verify-contract 对空地址只会报难以定位的错误。
for field in GROUP_CHAT_DELEGATE_ADDRESS GROUP_ADMIN_ADDRESS GROUP_CHAT_ADDRESS \
    GROUP_CHAT_BAN_LIST_ADDRESS ADMIN_BAN_SOURCE_ADDRESS GOV_VOTED_BAN_SOURCE_ADDRESS \
    GROUP_MEMBER_ADDRESS GROUP_MEMBER_SCOPE_ADDRESS GROUP_JOIN_SCOPE_SOURCE_ADDRESS \
    TOKEN_MAIN_MANAGER_ADDRESS TOKEN_GOV_MANAGER_ADDRESS TOKEN_ACTION_GOV_MANAGER_ADDRESS \
    TOKEN_ACTION_MAIN_MANAGER_ADDRESS; do
    if [[ ! ${!field:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ ${!field:-} = 0x0000000000000000000000000000000000000000 ]]; then
        echo "Error: Missing or invalid $field in $NETWORK_DIR/addresses.group-chat.params"
        exit 1
    fi
done

# 插件槽位是必填键（零地址=未挂载）：缺键时不能按零地址编码构造参数，否则验证的实参与部署实参不一致。
before_post_plugin="$GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS"
after_post_plugin="$GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS"

# 构造参数与 DeployGroupChat.s.sol 的部署实参一一对应；编码失败在命令替换下会静默中止，
# 故逐个显式判别，保证失败有明确输出。
encode_args() {
    local description="$1"
    shift
    if ! ENCODED=$(cast abi-encode "$@"); then
        echo "Error: Failed to encode constructor arguments for $description"
        exit 1
    fi
}

encode_args "GroupChatDelegate" "constructor(address)" "$MEMBER_NFT_ADDRESS"
DELEGATE_ARGS="$ENCODED"
encode_args "GroupAdmin" "constructor(address,uint256)" "$GROUP_CHAT_DELEGATE_ADDRESS" "$GROUP_CHAT_MAX_ADMIN_IDS"
ADMIN_ARGS="$ENCODED"
encode_args "GroupChat" "constructor(address,address,uint256,uint256)" \
    "$GROUP_ADMIN_ADDRESS" "$PHASE_ADDRESS" "$GROUP_CHAT_MAX_CONTENT_LENGTH" "$GROUP_CHAT_MAX_MENTIONED_SENDER_IDS"
CHAT_ARGS="$ENCODED"
encode_args "GroupChatBanList" "constructor(address)" "$GROUP_ADMIN_ADDRESS"
BANLIST_ARGS="$ENCODED"
encode_args "AdminBanSource" "constructor(address)" "$GROUP_CHAT_BAN_LIST_ADDRESS"
ADMINBANSOURCE_ARGS="$ENCODED"
encode_args "GovVotedBanSource" "constructor(address,uint256,uint256)" \
    "$MEMBER_NFT_ADDRESS" "$GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER" "$GROUP_CHAT_BAN_THRESHOLD_RATIO"
GOVVOTEDBANSOURCE_ARGS="$ENCODED"
encode_args "GroupMember" "constructor(address)" "$GROUP_ADMIN_ADDRESS"
MEMBER_ARGS="$ENCODED"
encode_args "GroupMemberScope" "constructor(address)" "$GROUP_MEMBER_ADDRESS"
MEMBERSCOPE_ARGS="$ENCODED"
encode_args "GroupJoinScopeSource" "constructor(address,address)" \
    "$GROUP_MEMBER_ADDRESS" "$GROUP_ACTION_EXECUTOR_ADDRESS"
JOINSCOPESOURCE_ARGS="$ENCODED"
encode_args "TokenMainManager" "constructor(address,address,address,address,address)" \
    "$GROUP_CHAT_ADDRESS" "$GOV_VOTED_BAN_SOURCE_ADDRESS" "$before_post_plugin" "$after_post_plugin" \
    "$ACTION_TARGET_ADDRESS"
MAINMANAGER_ARGS="$ENCODED"
encode_args "TokenGovManager" "constructor(address,address,address,address,address)" \
    "$GROUP_CHAT_ADDRESS" "$GOV_VOTED_BAN_SOURCE_ADDRESS" "$before_post_plugin" "$after_post_plugin" \
    "$ACTION_TARGET_ADDRESS"
GOVMANAGER_ARGS="$ENCODED"
encode_args "TokenActionGovManager" "constructor(address,address,address,address,address,uint256)" \
    "$GROUP_CHAT_ADDRESS" "$GOV_VOTED_BAN_SOURCE_ADDRESS" "$before_post_plugin" "$after_post_plugin" \
    "$ACTION_TARGET_ADDRESS" "$GROUP_CHAT_ACTION_RECENT_ROUNDS"
ACTIONGOVMANAGER_ARGS="$ENCODED"
encode_args "TokenActionMainManager" "constructor(address,address,address,address,address,uint256)" \
    "$GROUP_CHAT_ADDRESS" "$GOV_VOTED_BAN_SOURCE_ADDRESS" "$before_post_plugin" "$after_post_plugin" \
    "$ACTION_TARGET_ADDRESS" "$GROUP_CHAT_ACTION_RECENT_ROUNDS"
ACTIONMAINMANAGER_ARGS="$ENCODED"

# --watch 轮询验证结果：被拒时步骤失败，不把提交当成功。
COMMON_ARGS=(--chain "$CHAIN_ID" --verifier "$VERIFIER" --verifier-url "$VERIFIER_URL" --watch)
verify_contract() {
    local address=$1 name=$2 path=$3 args=$4
    echo "Verifying $name at $address..."
    forge verify-contract "$address" "$path:$name" "${COMMON_ARGS[@]}" --constructor-args "$args"
}

# GroupChatDelegate 与 GroupChatBanList 是本库新加入部署流程的合约。
verify_contract "$GROUP_CHAT_DELEGATE_ADDRESS" GroupChatDelegate "src/GroupChatDelegate.sol" "$DELEGATE_ARGS"
verify_contract "$GROUP_ADMIN_ADDRESS" GroupAdmin "src/GroupAdmin.sol" "$ADMIN_ARGS"
verify_contract "$GROUP_CHAT_ADDRESS" GroupChat "src/GroupChat.sol" "$CHAT_ARGS"
verify_contract "$GROUP_CHAT_BAN_LIST_ADDRESS" GroupChatBanList "src/GroupChatBanList.sol" "$BANLIST_ARGS"
verify_contract "$ADMIN_BAN_SOURCE_ADDRESS" AdminBanSource "src/sources/ban/AdminBanSource.sol" "$ADMINBANSOURCE_ARGS"
verify_contract "$GOV_VOTED_BAN_SOURCE_ADDRESS" GovVotedBanSource "src/sources/ban/GovVotedBanSource.sol" "$GOVVOTEDBANSOURCE_ARGS"
verify_contract "$GROUP_MEMBER_ADDRESS" GroupMember "src/GroupMember.sol" "$MEMBER_ARGS"
verify_contract "$GROUP_MEMBER_SCOPE_ADDRESS" GroupMemberScope "src/sources/scope/GroupMemberScope.sol" "$MEMBERSCOPE_ARGS"
verify_contract "$GROUP_JOIN_SCOPE_SOURCE_ADDRESS" GroupJoinScopeSource "src/sources/scope/GroupJoinScopeSource.sol" "$JOINSCOPESOURCE_ARGS"
verify_contract "$TOKEN_MAIN_MANAGER_ADDRESS" TokenMainManager "src/managers/TokenMainManager.sol" "$MAINMANAGER_ARGS"
verify_contract "$TOKEN_GOV_MANAGER_ADDRESS" TokenGovManager "src/managers/TokenGovManager.sol" "$GOVMANAGER_ARGS"
verify_contract "$TOKEN_ACTION_GOV_MANAGER_ADDRESS" TokenActionGovManager "src/managers/TokenActionGovManager.sol" "$ACTIONGOVMANAGER_ARGS"
verify_contract "$TOKEN_ACTION_MAIN_MANAGER_ADDRESS" TokenActionMainManager "src/managers/TokenActionMainManager.sol" "$ACTIONMAINMANAGER_ARGS"

echo "✓ Source verification succeeded for all 13 contracts"
