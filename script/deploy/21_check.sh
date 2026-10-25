#!/usr/bin/env bash
set -euo pipefail

# 步骤二：部署与初始化正确性校验。只读配置与链上状态，可重复运行。自包含——自行载入校验所需
# 文件，不依赖调用方预载环境：network.params 提供 RPC 与链 ID，addresses.core.params /
# addresses.action.params 提供期望的被依赖方绑定，group-chat.params 提供期望的构造参数，
# addresses.group-chat.params 提供待校验的已部署地址。
# 用法：script/deploy/21_check.sh <network>

network="${1:?usage: script/deploy/21_check.sh <network>}"

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

# 地址文件的键集合必须与期望合约集合一致：键名漏改会让后续变量静默为空，
# 逐项 cast 调用要到很后面才以难以定位的形式失败，故在此显式断言。
address_file="$NETWORK_DIR/addresses.group-chat.params"
expected_keys="ADMIN_BAN_SOURCE_ADDRESS GOV_VOTED_BAN_SOURCE_ADDRESS GROUP_ADMIN_ADDRESS \
GROUP_CHAT_BAN_LIST_ADDRESS GROUP_CHAT_DELEGATE_ADDRESS GROUP_CHAT_ADDRESS \
GROUP_JOIN_SCOPE_SOURCE_ADDRESS GROUP_MEMBER_SCOPE_ADDRESS GROUP_MEMBER_ADDRESS \
TOKEN_ACTION_GOV_MANAGER_ADDRESS TOKEN_ACTION_MAIN_MANAGER_ADDRESS TOKEN_GOV_MANAGER_ADDRESS \
TOKEN_MAIN_MANAGER_ADDRESS"
actual_keys=$(grep -oE '^[A-Z0-9_]+=' "$address_file" | sed 's/=$//' | sort | tr '\n' ' ' || true)
if [ "$actual_keys" != "$(printf '%s\n' $expected_keys | sort | tr '\n' ' ')" ]; then
    echo "Error: $address_file key set mismatch"
    echo "  expected: $(printf '%s\n' $expected_keys | sort | tr '\n' ' ')"
    echo "  actual:   $actual_keys"
    exit 1
fi

ACTUAL_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL") || exit 1
if [ "$ACTUAL_CHAIN_ID" != "$CHAIN_ID" ]; then
    echo "Error: RPC chain ID $ACTUAL_CHAIN_ID does not match configured CHAIN_ID $CHAIN_ID"
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

failed_checks=0

# 与部署脚本同口径：1 字节分隔符 + 4 位 hex + 4 字节 Test 前缀。
MANAGER_NAME_RESERVED_BYTES=9

cast_call() {
    cast call "$1" "$2" --rpc-url "$RPC_URL"
}

# cast 对 uint 返回值会带科学计数法标注（形如 [1e18]），比对前先剥掉，
# 否则 "1000000000000000000" 与 "1000000000000000000 [1e18]" 会被判为不一致。
strip_sci_notation() {
    echo "$1" | sed -E 's/\[[0-9.]+e[0-9]+\]//g' | tr -d ' '
}

check_equal() {
    local description="$1" expected="$2" actual="$3"

    expected=$(strip_sci_notation "$expected" | tr '[:upper:]' '[:lower:]')
    actual=$(strip_sci_notation "$actual" | tr '[:upper:]' '[:lower:]')
    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

check_contract_code() {
    local description="$1" address="$2" code
    code=$(cast code "$address" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ -n "$code" ] && [ "$code" != "0x" ]; then
        echo -e "${GREEN}✓${NC} $description ($address)"
        return 0
    else
        echo -e "${RED}✗${NC} $description has no code ($address)"
        return 1
    fi
}

echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Verifying GroupChat Deployment     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

echo "Verifying deployed contract code..."
for field in GROUP_CHAT_DELEGATE_ADDRESS GROUP_ADMIN_ADDRESS GROUP_CHAT_ADDRESS \
    GROUP_CHAT_BAN_LIST_ADDRESS ADMIN_BAN_SOURCE_ADDRESS GOV_VOTED_BAN_SOURCE_ADDRESS \
    GROUP_MEMBER_ADDRESS GROUP_MEMBER_SCOPE_ADDRESS GROUP_JOIN_SCOPE_SOURCE_ADDRESS \
    TOKEN_MAIN_MANAGER_ADDRESS TOKEN_GOV_MANAGER_ADDRESS TOKEN_ACTION_GOV_MANAGER_ADDRESS \
    TOKEN_ACTION_MAIN_MANAGER_ADDRESS; do
    check_contract_code "$field" "${!field}" || ((failed_checks += 1))
done
echo ""

echo "Verifying core / action dependency bindings..."

check_equal "GroupChatDelegate: GROUP_ADDRESS" "$MEMBER_NFT_ADDRESS" \
    "$(cast_call "$GROUP_CHAT_DELEGATE_ADDRESS" "GROUP_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupChat: GROUP_ADDRESS" "$MEMBER_NFT_ADDRESS" \
    "$(cast_call "$GROUP_CHAT_ADDRESS" "GROUP_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupAdmin: GROUP_ADDRESS" "$MEMBER_NFT_ADDRESS" \
    "$(cast_call "$GROUP_ADMIN_ADDRESS" "GROUP_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupMember: GROUP_ADDRESS" "$MEMBER_NFT_ADDRESS" \
    "$(cast_call "$GROUP_MEMBER_ADDRESS" "GROUP_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GovVotedBanSource: GROUP_ADDRESS" "$MEMBER_NFT_ADDRESS" \
    "$(cast_call "$GOV_VOTED_BAN_SOURCE_ADDRESS" "GROUP_ADDRESS()(address)")" || ((failed_checks += 1))

# 名称空间下限按各 Manager 的 TYPE_CODE() 派生，在下方 Manager 循环中校验。
member_love20_address=$(cast_call "$MEMBER_NFT_ADDRESS" "LOVE20_TOKEN_ADDRESS()(address)")
check_contract_code "MemberNFT: LOVE20_TOKEN_ADDRESS" "$member_love20_address" || ((failed_checks += 1))
check_equal "MemberNFT: LOVE20_TOKEN_ADDRESS == core" "$LOVE20_TOKEN_ADDRESS" \
    "$member_love20_address" || ((failed_checks += 1))

member_max_name_length=$(cast_call "$MEMBER_NFT_ADDRESS" "MAX_NAME_LENGTH()(uint256)" 2>/dev/null || echo "")
member_max_name_length=$(strip_sci_notation "$member_max_name_length")
if [[ ! "$member_max_name_length" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}✗${NC} MemberNFT: MAX_NAME_LENGTH query failed or invalid"
    ((failed_checks += 1))
fi
echo ""

check_equal "GroupChat: GROUP_ADMIN_ADDRESS" "$GROUP_ADMIN_ADDRESS" \
    "$(cast_call "$GROUP_CHAT_ADDRESS" "GROUP_ADMIN_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupChat: GROUP_DELEGATE_ADDRESS" "$GROUP_CHAT_DELEGATE_ADDRESS" \
    "$(cast_call "$GROUP_CHAT_ADDRESS" "GROUP_DELEGATE_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupChat: PHASE_ADDRESS" "$PHASE_ADDRESS" \
    "$(cast_call "$GROUP_CHAT_ADDRESS" "PHASE_ADDRESS()(address)")" || ((failed_checks += 1))
phase_origin_blocks=$(cast_call "$PHASE_ADDRESS" "ORIGIN_PHASE_BLOCKS()(uint256)")
if [[ ! "$(strip_sci_notation "$phase_origin_blocks")" =~ ^[0-9]+$ ]] \
    || [ "$(strip_sci_notation "$phase_origin_blocks")" -eq 0 ]; then
    echo -e "${RED}✗${NC} Phase: ORIGIN_PHASE_BLOCKS > 0 (actual: $phase_origin_blocks)"
    ((failed_checks += 1))
else
    echo -e "${GREEN}✓${NC} Phase: ORIGIN_PHASE_BLOCKS (actual: $phase_origin_blocks)"
fi
check_equal "GroupAdmin: GROUP_DELEGATE_ADDRESS" "$GROUP_CHAT_DELEGATE_ADDRESS" \
    "$(cast_call "$GROUP_ADMIN_ADDRESS" "GROUP_DELEGATE_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupAdmin: MAX_ADMIN_IDS" "$GROUP_CHAT_MAX_ADMIN_IDS" \
    "$(cast_call "$GROUP_ADMIN_ADDRESS" "MAX_ADMIN_IDS()(uint256)")" || ((failed_checks += 1))
echo ""

check_equal "GroupChat: MAX_CONTENT_LENGTH" "$GROUP_CHAT_MAX_CONTENT_LENGTH" \
    "$(cast_call "$GROUP_CHAT_ADDRESS" "MAX_CONTENT_LENGTH()(uint256)")" || ((failed_checks += 1))
check_equal "GroupChat: MAX_MENTIONED_SENDER_IDS" "$GROUP_CHAT_MAX_MENTIONED_SENDER_IDS" \
    "$(cast_call "$GROUP_CHAT_ADDRESS" "MAX_MENTIONED_SENDER_IDS()(uint256)")" || ((failed_checks += 1))
echo ""

check_equal "GroupChatBanList: GROUP_ADMIN_ADDRESS" "$GROUP_ADMIN_ADDRESS" \
    "$(cast_call "$GROUP_CHAT_BAN_LIST_ADDRESS" "GROUP_ADMIN_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "AdminBanSource: GROUP_BAN_LIST_ADDRESS" "$GROUP_CHAT_BAN_LIST_ADDRESS" \
    "$(cast_call "$ADMIN_BAN_SOURCE_ADDRESS" "GROUP_BAN_LIST_ADDRESS()(address)")" || ((failed_checks += 1))
echo ""

check_equal "GovVotedBanSource: PRECISION" "1000000000000000000" \
    "$(cast_call "$GOV_VOTED_BAN_SOURCE_ADDRESS" "PRECISION()(uint256)")" || ((failed_checks += 1))
check_equal "GovVotedBanSource: MIN_SUPPORT_TO_OPPOSE_MULTIPLIER" "$GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER" \
    "$(cast_call "$GOV_VOTED_BAN_SOURCE_ADDRESS" "MIN_SUPPORT_TO_OPPOSE_MULTIPLIER()(uint256)")" || ((failed_checks += 1))
check_equal "GovVotedBanSource: BAN_THRESHOLD_RATIO" "$GROUP_CHAT_BAN_THRESHOLD_RATIO" \
    "$(cast_call "$GOV_VOTED_BAN_SOURCE_ADDRESS" "BAN_THRESHOLD_RATIO()(uint256)")" || ((failed_checks += 1))
if [[ ! "$GROUP_CHAT_BAN_THRESHOLD_RATIO" =~ ^[0-9]+$ ]] \
    || [ "$GROUP_CHAT_BAN_THRESHOLD_RATIO" -gt 1000000000000000000 ]; then
    echo -e "${RED}✗${NC} GovVotedBanSource: BAN_THRESHOLD_RATIO <= 1e18 (actual: $GROUP_CHAT_BAN_THRESHOLD_RATIO)"
    ((failed_checks += 1))
else
    echo -e "${GREEN}✓${NC} GovVotedBanSource: BAN_THRESHOLD_RATIO <= 1e18"
fi
for field in GROUP_CHAT_ACTION_RECENT_ROUNDS GROUP_CHAT_MAX_CONTENT_LENGTH \
    GROUP_CHAT_MAX_MENTIONED_SENDER_IDS GROUP_CHAT_MAX_ADMIN_IDS \
    GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER; do
    value="${!field}"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "$value" -eq 0 ]; then
        echo -e "${RED}✗${NC} $field must be positive (actual: $value)"
        ((failed_checks += 1))
    else
        echo -e "${GREEN}✓${NC} $field is positive"
    fi
done
echo ""

check_equal "GroupMember: GROUP_ADMIN_ADDRESS" "$GROUP_ADMIN_ADDRESS" \
    "$(cast_call "$GROUP_MEMBER_ADDRESS" "GROUP_ADMIN_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupMemberScope: GROUP_MEMBER_ADDRESS" "$GROUP_MEMBER_ADDRESS" \
    "$(cast_call "$GROUP_MEMBER_SCOPE_ADDRESS" "GROUP_MEMBER_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupJoinScopeSource: GROUP_MEMBER_ADDRESS" "$GROUP_MEMBER_ADDRESS" \
    "$(cast_call "$GROUP_JOIN_SCOPE_SOURCE_ADDRESS" "GROUP_MEMBER_ADDRESS()(address)")" || ((failed_checks += 1))
check_equal "GroupJoinScopeSource: GROUP_ACTION_EXECUTOR_ADDRESS" "$GROUP_ACTION_EXECUTOR_ADDRESS" \
    "$(cast_call "$GROUP_JOIN_SCOPE_SOURCE_ADDRESS" "GROUP_ACTION_EXECUTOR_ADDRESS()(address)")" || ((failed_checks += 1))
echo ""

echo "Verifying ActionTarget bindings..."
check_contract_code "ActionTarget" "$ACTION_TARGET_ADDRESS" || ((failed_checks += 1))
check_contract_code "GroupActionExecutor" "$GROUP_ACTION_EXECUTOR_ADDRESS" || ((failed_checks += 1))
# ActionTarget 暴露 memberNFT/phase/submit/vote 四个地址；四个都应与 core 地址文件一致，
# 并继续校验 Vote.stakeAddress / Stake.launchAddress 的派生链。
check_equal "ActionTarget: memberNFTAddress" "$MEMBER_NFT_ADDRESS" \
    "$(cast_call "$ACTION_TARGET_ADDRESS" "memberNFTAddress()(address)")" || ((failed_checks += 1))
check_equal "ActionTarget: phaseAddress" "$PHASE_ADDRESS" \
    "$(cast_call "$ACTION_TARGET_ADDRESS" "phaseAddress()(address)")" || ((failed_checks += 1))
action_target_submit_address=$(cast_call "$ACTION_TARGET_ADDRESS" "submitAddress()(address)")
action_target_vote_address=$(cast_call "$ACTION_TARGET_ADDRESS" "voteAddress()(address)")
check_contract_code "ActionTarget: submitAddress" "$action_target_submit_address" || ((failed_checks += 1))
check_contract_code "ActionTarget: voteAddress" "$action_target_vote_address" || ((failed_checks += 1))
check_equal "ActionTarget: submitAddress == SUBMIT_ADDRESS" "$SUBMIT_ADDRESS" \
    "$action_target_submit_address" || ((failed_checks += 1))
check_equal "ActionTarget: voteAddress == VOTE_ADDRESS" "$VOTE_ADDRESS" \
    "$action_target_vote_address" || ((failed_checks += 1))
vote_stake_address=$(cast_call "$VOTE_ADDRESS" "stakeAddress()(address)")
check_equal "Vote: stakeAddress == STAKE_ADDRESS" "$STAKE_ADDRESS" "$vote_stake_address" || ((failed_checks += 1))
stake_launch_address=$(cast_call "$STAKE_ADDRESS" "launchAddress()(address)")
check_equal "Stake: launchAddress == LAUNCH_ADDRESS" "$LAUNCH_ADDRESS" \
    "$stake_launch_address" || ((failed_checks += 1))
echo -e "  SUBMIT_ADDRESS: $action_target_submit_address"
echo -e "  VOTE_ADDRESS:   $action_target_vote_address"
echo -e "  STAKE_ADDRESS:  $vote_stake_address"
echo -e "  LAUNCH_ADDRESS: $stake_launch_address"
echo ""

echo "Verifying manager immutable configuration..."
for plugin in GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS; do
    plugin_address="${!plugin:-0x0000000000000000000000000000000000000000}"
    if [ "$plugin_address" != "0x0000000000000000000000000000000000000000" ]; then
        check_contract_code "$plugin" "$plugin_address" || ((failed_checks += 1))
    fi
done
for manager in TOKEN_MAIN_MANAGER TOKEN_GOV_MANAGER TOKEN_ACTION_GOV_MANAGER TOKEN_ACTION_MAIN_MANAGER; do
    manager_address_field="${manager}_ADDRESS"
    manager_address="${!manager_address_field}"
    check_equal "$manager: GROUP_CHAT_ADDRESS" "$GROUP_CHAT_ADDRESS" \
        "$(cast_call "$manager_address" "GROUP_CHAT_ADDRESS()(address)")" || ((failed_checks += 1))
    check_equal "$manager: GROUP_ADDRESS" "$MEMBER_NFT_ADDRESS" \
        "$(cast_call "$manager_address" "GROUP_ADDRESS()(address)")" || ((failed_checks += 1))
    check_equal "$manager: BAN_SOURCE_ADDRESS" "$GOV_VOTED_BAN_SOURCE_ADDRESS" \
        "$(cast_call "$manager_address" "BAN_SOURCE_ADDRESS()(address)")" || ((failed_checks += 1))
    check_equal "$manager: BEFORE_POST_PLUGIN_ADDRESS" "${GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS:-0x0000000000000000000000000000000000000000}" \
        "$(cast_call "$manager_address" "BEFORE_POST_PLUGIN_ADDRESS()(address)")" || ((failed_checks += 1))
    check_equal "$manager: AFTER_POST_PLUGIN_ADDRESS" "${GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS:-0x0000000000000000000000000000000000000000}" \
        "$(cast_call "$manager_address" "AFTER_POST_PLUGIN_ADDRESS()(address)")" || ((failed_checks += 1))
    type_code=$(cast_call "$manager_address" "TYPE_CODE()(string)" 2>/dev/null | tr -d '"' || echo "")
    type_code_length=$(printf '%s' "$type_code" | wc -c | tr -d ' ')
    if [ -z "$type_code" ]; then
        echo -e "${RED}✗${NC} $manager: TYPE_CODE unavailable"
        ((failed_checks += 1))
    elif [[ ! "$member_max_name_length" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗${NC} $manager: MemberNFT MAX_NAME_LENGTH unavailable, name space unchecked"
        ((failed_checks += 1))
    else
        required_name_length=$((type_code_length + MANAGER_NAME_RESERVED_BYTES))
        if [ "$member_max_name_length" -lt "$required_name_length" ]; then
            echo -e "${RED}✗${NC} $manager: MAX_NAME_LENGTH >= TYPE_CODE.length + $MANAGER_NAME_RESERVED_BYTES (required: $required_name_length, actual: $member_max_name_length)"
            ((failed_checks += 1))
        else
            echo -e "${GREEN}✓${NC} $manager: TYPE_CODE '$type_code' fits MAX_NAME_LENGTH ($member_max_name_length >= $required_name_length)"
        fi
    fi
    echo ""
done

check_equal "TokenActionGovManager: RECENT_ROUNDS" "$GROUP_CHAT_ACTION_RECENT_ROUNDS" \
    "$(cast_call "$TOKEN_ACTION_GOV_MANAGER_ADDRESS" "RECENT_ROUNDS()(uint256)")" || ((failed_checks += 1))
check_equal "TokenActionMainManager: RECENT_ROUNDS" "$GROUP_CHAT_ACTION_RECENT_ROUNDS" \
    "$(cast_call "$TOKEN_ACTION_MAIN_MANAGER_ADDRESS" "RECENT_ROUNDS()(uint256)")" || ((failed_checks += 1))
echo ""

echo "Verifying the round source..."
actual_round=$(cast_call "$GROUP_CHAT_ADDRESS" "currentRound()(uint256)" 2>/dev/null || echo "")
if [ -n "$actual_round" ]; then
    echo -e "${GREEN}✓${NC} GroupChat: currentRound ($actual_round)"
    phase_round=$(cast_call "$PHASE_ADDRESS" "currentPhase()(uint256)" 2>/dev/null || echo "")
    if [ -n "$phase_round" ]; then
        check_equal "GroupChat: currentRound matches Phase" "$phase_round" "$actual_round" || ((failed_checks += 1))
    else
        echo -e "${RED}✗${NC} Phase: currentPhase unavailable; cannot prove round alignment"
        ((failed_checks += 1))
    fi
else
    echo -e "${RED}✗${NC} GroupChat: currentRound reverted; the current block is before the Phase origin"
    ((failed_checks += 1))
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
if [ "$failed_checks" -eq 0 ]; then
    echo -e "${GREEN}✓ All parameter checks passed${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    exit 0
else
    echo -e "${RED}✗ $failed_checks check(s) failed${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    exit 1
fi
