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

set -a
source "$NETWORK_DIR/network.params"
source "$NETWORK_DIR/addresses.core.params"
source "$NETWORK_DIR/addresses.action.params"
source "$NETWORK_DIR/group-chat.params"
source "$NETWORK_DIR/addresses.group-chat.params"
set +a

cd "$PROJECT_ROOT"

# network.params 未提供 verifier 的链不适用例（本地 anvil、未接入浏览器的链），直接跳过。
if [ -z "${VERIFIER:-}" ] || [ -z "${VERIFIER_URL:-}" ]; then
    echo "Skip: source verification is not configured for chain $CHAIN_ID"
    exit 0
fi

# 13 个合约地址缺项即失败：forge verify-contract 对空地址只会报难以定位的错误。
for field in GROUPCHATDELEGATE_ADDRESS GROUPADMIN_ADDRESS GROUPCHAT_ADDRESS \
    GROUPCHATBANLIST_ADDRESS ADMINBANSOURCE_ADDRESS GOVVOTEDBANSOURCE_ADDRESS \
    GROUPMEMBER_ADDRESS GROUPMEMBERSCOPE_ADDRESS GROUPJOINSCOPESOURCE_ADDRESS \
    TOKENMAINMANAGER_ADDRESS TOKENGOVMANAGER_ADDRESS TOKENACTIONGOVMANAGER_ADDRESS \
    TOKENACTIONMAINMANAGER_ADDRESS; do
    if [[ ! ${!field:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ ${!field:-} = 0x0000000000000000000000000000000000000000 ]]; then
        echo "Error: Missing or invalid $field in $NETWORK_DIR/addresses.group-chat.params"
        exit 1
    fi
done

# 插件槽位未配置时按 DeployGroupChat.s.sol 的 envOr 默认值取零地址。
before_post_plugin="${GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS:-0x0000000000000000000000000000000000000000}"
after_post_plugin="${GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS:-0x0000000000000000000000000000000000000000}"

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

encode_args "GroupChatDelegate" "constructor(address)" "$GROUP_ADDRESS"
DELEGATE_ARGS="$ENCODED"
encode_args "GroupAdmin" "constructor(address,uint256)" "$GROUPCHATDELEGATE_ADDRESS" "$GROUP_CHAT_MAX_ADMIN_IDS"
ADMIN_ARGS="$ENCODED"
encode_args "GroupChat" "constructor(address,address,uint256,uint256)" \
    "$GROUPADMIN_ADDRESS" "$PHASE_ADDRESS" "$GROUP_CHAT_MAX_CONTENT_LENGTH" "$GROUP_CHAT_MAX_MENTIONED_SENDER_IDS"
CHAT_ARGS="$ENCODED"
encode_args "GroupChatBanList" "constructor(address)" "$GROUPADMIN_ADDRESS"
BANLIST_ARGS="$ENCODED"
encode_args "AdminBanSource" "constructor(address)" "$GROUPCHATBANLIST_ADDRESS"
ADMINBANSOURCE_ARGS="$ENCODED"
encode_args "GovVotedBanSource" "constructor(address,uint256,uint256)" \
    "$GROUP_ADDRESS" "$GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER" "$GROUP_CHAT_BAN_THRESHOLD_RATIO"
GOVVOTEDBANSOURCE_ARGS="$ENCODED"
encode_args "GroupMember" "constructor(address)" "$GROUPADMIN_ADDRESS"
MEMBER_ARGS="$ENCODED"
encode_args "GroupMemberScope" "constructor(address)" "$GROUPMEMBER_ADDRESS"
MEMBERSCOPE_ARGS="$ENCODED"
encode_args "GroupJoinScopeSource" "constructor(address,address)" \
    "$GROUPMEMBER_ADDRESS" "$GROUP_ACTION_EXECUTOR_ADDRESS"
JOINSCOPESOURCE_ARGS="$ENCODED"
encode_args "TokenMainManager" "constructor(address,address,address,address,address)" \
    "$GROUPCHAT_ADDRESS" "$GOVVOTEDBANSOURCE_ADDRESS" "$before_post_plugin" "$after_post_plugin" \
    "$ACTION_TARGET_ADDRESS"
MAINMANAGER_ARGS="$ENCODED"
encode_args "TokenGovManager" "constructor(address,address,address,address,address)" \
    "$GROUPCHAT_ADDRESS" "$GOVVOTEDBANSOURCE_ADDRESS" "$before_post_plugin" "$after_post_plugin" \
    "$ACTION_TARGET_ADDRESS"
GOVMANAGER_ARGS="$ENCODED"
encode_args "TokenActionGovManager" "constructor(address,address,address,address,address,uint256)" \
    "$GROUPCHAT_ADDRESS" "$GOVVOTEDBANSOURCE_ADDRESS" "$before_post_plugin" "$after_post_plugin" \
    "$ACTION_TARGET_ADDRESS" "$GROUP_CHAT_ACTION_RECENT_ROUNDS"
ACTIONGOVMANAGER_ARGS="$ENCODED"
encode_args "TokenActionMainManager" "constructor(address,address,address,address,address,uint256)" \
    "$GROUPCHAT_ADDRESS" "$GOVVOTEDBANSOURCE_ADDRESS" "$before_post_plugin" "$after_post_plugin" \
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
verify_contract "$GROUPCHATDELEGATE_ADDRESS" GroupChatDelegate "src/GroupChatDelegate.sol" "$DELEGATE_ARGS"
verify_contract "$GROUPADMIN_ADDRESS" GroupAdmin "src/GroupAdmin.sol" "$ADMIN_ARGS"
verify_contract "$GROUPCHAT_ADDRESS" GroupChat "src/GroupChat.sol" "$CHAT_ARGS"
verify_contract "$GROUPCHATBANLIST_ADDRESS" GroupChatBanList "src/GroupChatBanList.sol" "$BANLIST_ARGS"
verify_contract "$ADMINBANSOURCE_ADDRESS" AdminBanSource "src/sources/ban/AdminBanSource.sol" "$ADMINBANSOURCE_ARGS"
verify_contract "$GOVVOTEDBANSOURCE_ADDRESS" GovVotedBanSource "src/sources/ban/GovVotedBanSource.sol" "$GOVVOTEDBANSOURCE_ARGS"
verify_contract "$GROUPMEMBER_ADDRESS" GroupMember "src/GroupMember.sol" "$MEMBER_ARGS"
verify_contract "$GROUPMEMBERSCOPE_ADDRESS" GroupMemberScope "src/sources/scope/GroupMemberScope.sol" "$MEMBERSCOPE_ARGS"
verify_contract "$GROUPJOINSCOPESOURCE_ADDRESS" GroupJoinScopeSource "src/sources/scope/GroupJoinScopeSource.sol" "$JOINSCOPESOURCE_ARGS"
verify_contract "$TOKENMAINMANAGER_ADDRESS" TokenMainManager "src/managers/TokenMainManager.sol" "$MAINMANAGER_ARGS"
verify_contract "$TOKENGOVMANAGER_ADDRESS" TokenGovManager "src/managers/TokenGovManager.sol" "$GOVMANAGER_ARGS"
verify_contract "$TOKENACTIONGOVMANAGER_ADDRESS" TokenActionGovManager "src/managers/TokenActionGovManager.sol" "$ACTIONGOVMANAGER_ARGS"
verify_contract "$TOKENACTIONMAINMANAGER_ADDRESS" TokenActionMainManager "src/managers/TokenActionMainManager.sol" "$ACTIONMAINMANAGER_ARGS"

echo "✓ Source verification succeeded for all 13 contracts"
