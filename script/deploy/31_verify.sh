#!/usr/bin/env bash
set -euo pipefail

# Step 3: source verification. Self-contained: loads network.params, verifier.params, the dependency
# addresses, the constructor arguments and the addresses.group-chat.params written by the last
# deployment, without relying on the entrypoint to refresh addresses.
# Constructor arguments are encoded explicitly with cast abi-encode instead of relying on
# automatic detection from the broadcast artifact.
# Chains listed in VERIFY_SKIP_CHAIN_IDS skip the step and return success, so one-click deployment
# also works on local chains.
# Usage: script/deploy/31_verify.sh <network>

network="${1:?usage: script/deploy/31_verify.sh <network>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NETWORK_DIR="$PROJECT_ROOT/script/network/$network"
VERIFIER_PARAMS="$PROJECT_ROOT/script/network/verifier.params"

# Parameter file loader: 1e17 / 1_000_000 style literals are expanded to decimal on load (params.sh).
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
if [ ! -f "$VERIFIER_PARAMS" ]; then
    echo "Error: Missing required configuration: $VERIFIER_PARAMS"
    exit 1
fi

# Parameters come from files only: clear every key the files define, so a value exported by the
# caller cannot override a file value. The two plugin slots are the keys whose absence would change
# behaviour silently (a misspelled or blanked key would deploy a group without plugins), so both are
# asserted against the file itself, never against the variable - an inherited value could satisfy
# that. An empty value is rejected too: "not mounted" must be spelled as the zero address.
params_require_values "$NETWORK_DIR/group-chat.params" \
    GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS || exit 1

params_unset_all "$NETWORK_DIR/network.params" "$VERIFIER_PARAMS" \
    "$NETWORK_DIR/addresses.core.params" "$NETWORK_DIR/addresses.action.params" \
    "$NETWORK_DIR/group-chat.params" "$NETWORK_DIR/addresses.group-chat.params"

params_load "$NETWORK_DIR/network.params"
params_load "$VERIFIER_PARAMS"
params_load "$NETWORK_DIR/addresses.core.params"
params_load "$NETWORK_DIR/addresses.action.params"
params_load "$NETWORK_DIR/group-chat.params"
params_load "$NETWORK_DIR/addresses.group-chat.params"

cd "$PROJECT_ROOT"

# The opt-out list is mandatory as a key but may be empty: "verify every chain" is a legal answer.
params_require_keys "$VERIFIER_PARAMS" VERIFY_SKIP_CHAIN_IDS || exit 1

# Verification is attempted by default: only the chains listed here skip it, so a new production
# chain fails loudly instead of passing unverified.
skip_chains=",${VERIFY_SKIP_CHAIN_IDS:-},"
if [ -n "${CHAIN_ID:-}" ] && [[ "$skip_chains" == *",$CHAIN_ID,"* ]]; then
    echo "Skip: source verification is disabled for chain $CHAIN_ID in $VERIFIER_PARAMS"
    exit 0
fi

# The endpoint is a mandatory key: an empty URL would be passed straight to forge.
params_require_values "$VERIFIER_PARAMS" ETHERSCAN_VERIFIER_URL || exit 1
: "${ETHERSCAN_API_KEY:?Set an Etherscan API key; source verification has not run.}"

# Any missing address among the twelve fails the step: forge verify-contract only reports an
# unhelpful error for an empty address.
for field in GROUP_ADMIN_ADDRESS GROUP_CHAT_ADDRESS \
    GROUP_CHAT_BAN_LIST_ADDRESS ADMIN_BAN_SOURCE_ADDRESS GOV_VOTED_BAN_SOURCE_ADDRESS \
    GROUP_MEMBER_ADDRESS GROUP_MEMBER_SCOPE_ADDRESS GROUP_JOIN_SCOPE_SOURCE_ADDRESS \
    TOKEN_MAIN_MANAGER_ADDRESS TOKEN_GOV_MANAGER_ADDRESS TOKEN_ACTION_GOV_MANAGER_ADDRESS \
    TOKEN_ACTION_MAIN_MANAGER_ADDRESS; do
    if [[ ! ${!field:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ ${!field:-} = 0x0000000000000000000000000000000000000000 ]]; then
        echo "Error: Missing or invalid $field in $NETWORK_DIR/addresses.group-chat.params"
        exit 1
    fi
done

# Plugin slots are mandatory keys (zero address = not mounted): a missing key must not encode the
# zero address, or the verified arguments would differ from the deployed ones.
before_post_plugin="$GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS"
after_post_plugin="$GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS"

# The constructor arguments match the deployment arguments of DeployGroupChat.s.sol one to one; a
# failing encoding would silently abort inside a command substitution, so each call is checked
# explicitly for a clear message.
encode_args() {
    local description="$1"
    shift
    if ! ENCODED=$(cast abi-encode "$@"); then
        echo "Error: Failed to encode constructor arguments for $description"
        exit 1
    fi
}

encode_args "GroupAdmin" "constructor(address,uint256)" "$MEMBER_NFT_ADDRESS" "$GROUP_CHAT_MAX_ADMIN_IDS"
ADMIN_ARGS="$ENCODED"
encode_args "GroupChat" "constructor(address,address)" "$GROUP_ADMIN_ADDRESS" "$PHASE_ADDRESS"
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

# --watch polls the verification result: a rejection fails the step instead of treating the
# submission as success.
COMMON_ARGS=(--chain "$CHAIN_ID" --verifier etherscan --verifier-url "$ETHERSCAN_VERIFIER_URL" --watch)
verify_contract() {
    local address=$1 name=$2 path=$3 args=$4
    echo "Verifying $name at $address..."
    forge verify-contract "$address" "$path:$name" "${COMMON_ARGS[@]}" --constructor-args "$args"
}

# GroupChatBanList is the contract newly added to this repository's deployment flow.
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

echo "✓ Source verification succeeded for all 12 contracts"
