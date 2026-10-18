#!/usr/bin/env bash
set -euo pipefail

# 步骤三：合约开源验证。自包含——自行载入 network.params 与上次部署写入的
# addresses.group-chat.params，不依赖入口脚本在部署后刷新地址。
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

for config in network.params addresses.group-chat.params; do
    if [ ! -f "$NETWORK_DIR/$config" ]; then
        echo "Error: Missing required configuration: $NETWORK_DIR/$config"
        exit 1
    fi
done

set -a
source "$NETWORK_DIR/network.params"
source "$NETWORK_DIR/addresses.group-chat.params"
set +a

cd "$PROJECT_ROOT"

# network.params 未提供 verifier 的链不适用例（本地 anvil、未接入浏览器的链），直接跳过。
: "${VERIFIER:?Set VERIFIER in $NETWORK_DIR/network.params; source verification has not run.}"
: "${VERIFIER_URL:?Set VERIFIER_URL in $NETWORK_DIR/network.params; source verification has not run.}"
: "${ETHERSCAN_API_KEY:=}"

COMMON_ARGS=(--chain "$CHAIN_ID" --verifier "$VERIFIER" --verifier-url "$VERIFIER_URL")
verify_contract() {
    local address=$1 name=$2 path=$3
    echo "Verifying $name at $address..."
    forge verify-contract "$address" "$path:$name" "${COMMON_ARGS[@]}"
}

# address => 源码路径。GroupChatDelegate 与 GroupChatBanList 是本库新加入部署流程的合约。
verify_contract "$GROUPCHATDELEGATE_ADDRESS" GroupChatDelegate "src/GroupChatDelegate.sol"
verify_contract "$GROUPADMIN_ADDRESS" GroupAdmin "src/GroupAdmin.sol"
verify_contract "$GROUPCHAT_ADDRESS" GroupChat "src/GroupChat.sol"
verify_contract "$GROUPCHATBANLIST_ADDRESS" GroupChatBanList "src/GroupChatBanList.sol"
verify_contract "$ADMINBANSOURCE_ADDRESS" AdminBanSource "src/sources/ban/AdminBanSource.sol"
verify_contract "$GOVVOTEDBANSOURCE_ADDRESS" GovVotedBanSource "src/sources/ban/GovVotedBanSource.sol"
verify_contract "$GROUPMEMBER_ADDRESS" GroupMember "src/GroupMember.sol"
verify_contract "$GROUPMEMBERSCOPE_ADDRESS" GroupMemberScope "src/sources/scope/GroupMemberScope.sol"
verify_contract "$GROUPJOINSCOPESOURCE_ADDRESS" GroupJoinScopeSource "src/sources/scope/GroupJoinScopeSource.sol"
verify_contract "$TOKENMAINMANAGER_ADDRESS" TokenMainManager "src/managers/TokenMainManager.sol"
verify_contract "$TOKENGOVMANAGER_ADDRESS" TokenGovManager "src/managers/TokenGovManager.sol"
verify_contract "$TOKENACTIONGOVMANAGER_ADDRESS" TokenActionGovManager "src/managers/TokenActionGovManager.sol"
verify_contract "$TOKENACTIONMAINMANAGER_ADDRESS" TokenActionMainManager "src/managers/TokenActionMainManager.sol"

echo "✓ Source verification submitted for all 13 contracts"
