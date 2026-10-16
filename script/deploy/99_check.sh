#!/bin/bash

source ./lib.sh || return 1

echo "========================================="
echo "Verifying GroupChat Configuration"
echo "========================================="

if [ -n "$network_dir" ] && [ -f "$network_dir/address.group.chat.params" ] && { \
	    [ -z "$groupChatAddress" ] || \
	    [ -z "$groupAdminAddress" ] || \
	    [ -z "$groupBanListAddress" ] || \
	    [ -z "$adminBanSourceAddress" ] || \
    [ -z "$govVotedBanSourceAddress" ] || \
    [ -z "$groupMemberAddress" ] || \
    [ -z "$groupMemberScopeAddress" ] || \
    [ -z "$groupJoinScopeSourceAddress" ] || \
    [ -z "$tokenMainManagerAddress" ] || \
    [ -z "$tokenGovManagerAddress" ] || \
    [ -z "$tokenActionGovManagerAddress" ] || \
    [ -z "$tokenActionMainManagerAddress" ]; \
}; then
    load_env_file "$network_dir/address.group.chat.params" || return 1
fi

if [ -n "$network_dir" ] && [ -f "$network_dir/address.group.params" ]; then
    load_env_file "$network_dir/address.group.params" || return 1
fi

if [ -n "$network_dir" ] && [ -f "$network_dir/address.group.defaults.params" ]; then
    load_env_file "$network_dir/address.group.defaults.params" || return 1
fi

if [ -n "$network_dir" ] && [ -f "$network_dir/address.group.delegate.params" ]; then
    load_env_file "$network_dir/address.group.delegate.params" || return 1
fi

if [ -n "$network_dir" ] && [ -f "$network_dir/group.chat.params" ]; then
    load_env_file "$network_dir/group.chat.params" || return 1
else
    echo -e "\033[31mError:\033[0m group.chat.params not found; run 00_init.sh <network> before 99_check.sh"
    return 1
fi

if [ -n "$groupAddress" ]; then
    GROUP_ADDRESS=$groupAddress
    export GROUP_ADDRESS
fi

if [ -n "$groupDefaultsAddress" ]; then
    GROUP_DEFAULTS_ADDRESS=$groupDefaultsAddress
    export GROUP_DEFAULTS_ADDRESS
fi

if [ -n "$groupDelegateAddress" ]; then
    GROUP_DELEGATE_ADDRESS=$groupDelegateAddress
    export GROUP_DELEGATE_ADDRESS
fi

if [ -n "$extensionCenterAddress" ]; then
    EXTENSION_CENTER_ADDRESS=$extensionCenterAddress
    export EXTENSION_CENTER_ADDRESS
fi

if [ -n "$groupJoinAddress" ]; then
    GROUP_JOIN_ADDRESS=$groupJoinAddress
    export GROUP_JOIN_ADDRESS
fi

if [ -n "$groupAdminAddress" ]; then
    GROUP_ADMIN_ADDRESS=$groupAdminAddress
    export GROUP_ADMIN_ADDRESS
fi

if [ -n "$groupBanListAddress" ]; then
    GROUP_BAN_LIST_ADDRESS=$groupBanListAddress
    export GROUP_BAN_LIST_ADDRESS
fi

if [ -n "$groupMemberAddress" ]; then
    GROUP_MEMBER_ADDRESS=$groupMemberAddress
    export GROUP_MEMBER_ADDRESS
fi

if [ -n "$groupMemberScopeAddress" ]; then
    GROUP_MEMBER_SCOPE_ADDRESS=$groupMemberScopeAddress
    export GROUP_MEMBER_SCOPE_ADDRESS
fi

if [ -n "$groupJoinScopeSourceAddress" ]; then
    GROUP_JOIN_SCOPE_SOURCE_ADDRESS=$groupJoinScopeSourceAddress
    export GROUP_JOIN_SCOPE_SOURCE_ADDRESS
fi

if [ -n "$adminBanSourceAddress" ]; then
    ADMIN_BAN_SOURCE_ADDRESS=$adminBanSourceAddress
    export ADMIN_BAN_SOURCE_ADDRESS
fi

if [ -n "$groupChatBeforePostPluginAddress" ]; then
    GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS=$groupChatBeforePostPluginAddress
    export GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS
fi

if [ -n "$groupChatAfterPostPluginAddress" ]; then
    GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS=$groupChatAfterPostPluginAddress
    export GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS
fi

if [ -n "$actionRecentRounds" ]; then
    GROUP_CHAT_ACTION_RECENT_ROUNDS=$actionRecentRounds
    export GROUP_CHAT_ACTION_RECENT_ROUNDS
fi

if [ -n "$maxContentLength" ]; then
    GROUP_CHAT_MAX_CONTENT_LENGTH=$maxContentLength
    export GROUP_CHAT_MAX_CONTENT_LENGTH
fi

if [ -n "$maxMentionedSenderIds" ]; then
    GROUP_CHAT_MAX_MENTIONED_SENDER_IDS=$maxMentionedSenderIds
    export GROUP_CHAT_MAX_MENTIONED_SENDER_IDS
fi

if [ -n "$banThresholdRatio" ]; then
    GROUP_CHAT_BAN_THRESHOLD_RATIO=$banThresholdRatio
    export GROUP_CHAT_BAN_THRESHOLD_RATIO
fi

if [ -n "$minSupportToOpposeRatio" ]; then
    GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO=$minSupportToOpposeRatio
    export GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO
fi

if [ -n "$maxAdminIds" ]; then
    GROUP_CHAT_MAX_ADMIN_IDS=$maxAdminIds
    export GROUP_CHAT_MAX_ADMIN_IDS
fi

zero_address=0x0000000000000000000000000000000000000000

if [ -z "$GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS" ]; then
    GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS=$zero_address
    export GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS
fi

if [ -z "$GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS" ]; then
    GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS=$zero_address
    export GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS
fi

if [ -z "$GROUP_CHAT_BAN_THRESHOLD_RATIO" ]; then
    GROUP_CHAT_BAN_THRESHOLD_RATIO=3000000000000000
    export GROUP_CHAT_BAN_THRESHOLD_RATIO
fi

if [ -z "$GROUP_CHAT_MAX_CONTENT_LENGTH" ]; then
    GROUP_CHAT_MAX_CONTENT_LENGTH=4096
    export GROUP_CHAT_MAX_CONTENT_LENGTH
fi

if [ -z "$GROUP_CHAT_MAX_MENTIONED_SENDER_IDS" ]; then
    GROUP_CHAT_MAX_MENTIONED_SENDER_IDS=32
    export GROUP_CHAT_MAX_MENTIONED_SENDER_IDS
fi

if [ -z "$GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO" ]; then
    GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO=10
    export GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO
fi

if [ -z "$GROUP_CHAT_MAX_ADMIN_IDS" ]; then
    GROUP_CHAT_MAX_ADMIN_IDS=20
    export GROUP_CHAT_MAX_ADMIN_IDS
fi

if [ -z "$groupChatAddress" ]; then
    echo -e "\033[31mError:\033[0m GroupChat address not set"
    return 1
fi

echo "Validating initialization parameters..."
missing_params=0

if [ -z "$GROUP_DEFAULTS_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_DEFAULTS_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_DELEGATE_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_DELEGATE_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$EXTENSION_CENTER_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m EXTENSION_CENTER_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_CHAT_ACTION_RECENT_ROUNDS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_CHAT_ACTION_RECENT_ROUNDS not set"
    ((missing_params++))
fi

if [ -n "$GROUP_CHAT_ACTION_RECENT_ROUNDS" ] && [ "$GROUP_CHAT_ACTION_RECENT_ROUNDS" = "0" ]; then
    echo -e "\033[31m✗\033[0m GROUP_CHAT_ACTION_RECENT_ROUNDS must be greater than zero"
    ((missing_params++))
fi

if [ "$GROUP_CHAT_MAX_CONTENT_LENGTH" = "0" ]; then
    echo -e "\033[31m✗\033[0m GROUP_CHAT_MAX_CONTENT_LENGTH must be greater than zero"
    ((missing_params++))
fi

if [ "$GROUP_CHAT_MAX_ADMIN_IDS" = "0" ]; then
    echo -e "\033[31m✗\033[0m GROUP_CHAT_MAX_ADMIN_IDS must be greater than zero"
    ((missing_params++))
fi

if [ "$GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO" = "0" ]; then
    echo -e "\033[31m✗\033[0m GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO must be greater than zero"
    ((missing_params++))
fi

if [ -z "$govVotedBanSourceAddress" ]; then
    echo -e "\033[31m✗\033[0m govVotedBanSourceAddress not set"
    ((missing_params++))
fi

if [ -z "$GROUP_ADMIN_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_ADMIN_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_BAN_LIST_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_BAN_LIST_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_MEMBER_SCOPE_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_MEMBER_SCOPE_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_MEMBER_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_MEMBER_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_JOIN_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_JOIN_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_JOIN_SCOPE_SOURCE_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_JOIN_SCOPE_SOURCE_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$ADMIN_BAN_SOURCE_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m ADMIN_BAN_SOURCE_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS" ]; then
    echo -e "\033[31m✗\033[0m GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS not set"
    ((missing_params++))
fi

if [ -z "$tokenMainManagerAddress" ]; then
    echo -e "\033[31m✗\033[0m tokenMainManagerAddress not set"
    ((missing_params++))
fi

if [ -z "$tokenGovManagerAddress" ]; then
    echo -e "\033[31m✗\033[0m tokenGovManagerAddress not set"
    ((missing_params++))
fi

if [ -z "$tokenActionGovManagerAddress" ]; then
    echo -e "\033[31m✗\033[0m tokenActionGovManagerAddress not set"
    ((missing_params++))
fi

if [ -z "$tokenActionMainManagerAddress" ]; then
    echo -e "\033[31m✗\033[0m tokenActionMainManagerAddress not set"
    ((missing_params++))
fi

if [ $missing_params -gt 0 ]; then
    echo -e "\033[31mError:\033[0m $missing_params initialization parameter(s) missing"
    echo "Please ensure all parameters are loaded from group.chat.params / address.group.params / address.group.defaults.params / address.group.delegate.params / address.group.chat.params"
    return 1
fi

echo -e "\033[32m✓\033[0m All initialization parameters are set"
echo ""

echo -e "GroupChat Address: $groupChatAddress\n"
echo -e "GroupDelegate Address: $GROUP_DELEGATE_ADDRESS"
echo -e "GroupAdmin Address: $GROUP_ADMIN_ADDRESS"
echo -e "GroupBanList Address: $GROUP_BAN_LIST_ADDRESS"
echo -e "AdminBanSource Address: $ADMIN_BAN_SOURCE_ADDRESS"
echo -e "GovVotedBanSource Address: $govVotedBanSourceAddress\n"
echo -e "GroupMember Address: $GROUP_MEMBER_ADDRESS"
echo -e "GroupMemberScope Address: $GROUP_MEMBER_SCOPE_ADDRESS"
echo -e "GroupJoinScopeSource Address: $GROUP_JOIN_SCOPE_SOURCE_ADDRESS"
echo -e "GroupJoin Address: $GROUP_JOIN_ADDRESS\n"
echo -e "Ban Threshold Ratio: $GROUP_CHAT_BAN_THRESHOLD_RATIO\n"
echo -e "Min Support To Oppose Ratio: $GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO\n"
echo -e "Max Content Length: $GROUP_CHAT_MAX_CONTENT_LENGTH\n"
echo -e "Max Mentioned Sender Ids: $GROUP_CHAT_MAX_MENTIONED_SENDER_IDS\n"
echo -e "Max Admin Ids: $GROUP_CHAT_MAX_ADMIN_IDS\n"
echo -e "TokenMainManager Address: $tokenMainManagerAddress"
echo -e "TokenGovManager Address: $tokenGovManagerAddress"
echo -e "TokenActionGovManager Address: $tokenActionGovManagerAddress"
echo -e "TokenActionMainManager Address: $tokenActionMainManagerAddress\n"

failed_checks=0

check_contract_code() {
    local description="$1"
    local address="$2"
    local code

    code=$(cast code "$address" --rpc-url "$RPC_URL")

    if [ -n "$code" ] && [ "$code" != "0x" ]; then
        echo -e "\033[32m✓\033[0m $description"
        echo -e "  Address: $address"
        return 0
    else
        echo -e "\033[31m✗\033[0m $description"
        echo -e "  Address: $address"
        echo -e "  Code:    $code"
        return 1
    fi
}

center_launch_address=$(cast_call $EXTENSION_CENTER_ADDRESS "launchAddress()(address)")
center_stake_address=$(cast_call $EXTENSION_CENTER_ADDRESS "stakeAddress()(address)")
center_join_address=$(cast_call $EXTENSION_CENTER_ADDRESS "joinAddress()(address)")
center_vote_address=$(cast_call $EXTENSION_CENTER_ADDRESS "voteAddress()(address)")

echo "Verifying initialization parameters match contract values..."

defaults_group_address=$(cast_call $GROUP_DEFAULTS_ADDRESS "GROUP_ADDRESS()(address)")
if [ -n "$GROUP_ADDRESS" ]; then
    check_equal "GroupDefaults: GROUP_ADDRESS" "$GROUP_ADDRESS" "$defaults_group_address"
    [ $? -ne 0 ] && ((failed_checks++))
    echo ""
else
    GROUP_ADDRESS=$defaults_group_address
    export GROUP_ADDRESS
fi

check_equal "GroupChat: GROUP_ADDRESS" "$defaults_group_address" "$(cast_call "$groupChatAddress" "GROUP_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

check_equal "GroupChat: GROUP_ADMIN_ADDRESS" "$GROUP_ADMIN_ADDRESS" "$(cast_call "$groupChatAddress" "GROUP_ADMIN_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

check_equal "GroupChat: GROUP_DEFAULTS_ADDRESS" "$GROUP_DEFAULTS_ADDRESS" "$(cast_call "$groupChatAddress" "GROUP_DEFAULTS_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

check_equal "GroupChat: GROUP_DELEGATE_ADDRESS" "$GROUP_DELEGATE_ADDRESS" "$(cast_call "$groupChatAddress" "GROUP_DELEGATE_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

check_equal "GroupDelegate: GROUP_ADDRESS" "$GROUP_ADDRESS" "$(cast_call "$GROUP_DELEGATE_ADDRESS" "GROUP_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

group_chat_origin_blocks=$(cast_call $groupChatAddress "originBlocks()(uint256)")
group_chat_phase_blocks=$(cast_call $groupChatAddress "phaseBlocks()(uint256)")
core_join_origin_blocks=$(cast_call $center_join_address "originBlocks()(uint256)")
core_join_phase_blocks=$(cast_call $center_join_address "phaseBlocks()(uint256)")

check_equal "GroupChat: originBlocks matches core Join" "$core_join_origin_blocks" "$group_chat_origin_blocks"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

check_equal "GroupChat: phaseBlocks matches core Join" "$core_join_phase_blocks" "$group_chat_phase_blocks"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

check_equal "GroupChat: MAX_CONTENT_LENGTH" "$GROUP_CHAT_MAX_CONTENT_LENGTH" "$(cast_call "$groupChatAddress" "MAX_CONTENT_LENGTH()(uint256)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GroupChat: MAX_MENTIONED_SENDER_IDS" "$GROUP_CHAT_MAX_MENTIONED_SENDER_IDS" "$(cast_call "$groupChatAddress" "MAX_MENTIONED_SENDER_IDS()(uint256)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

actual_round=$(cast_call $groupChatAddress "currentRound()(uint256)" 2>/dev/null)
if [ -n "$actual_round" ]; then
    echo -e "\033[32m✓\033[0m GroupChat: currentRound"
    echo -e "  Actual: $actual_round"
    join_round=$(cast_call $center_join_address "currentRound()(uint256)" 2>/dev/null)
    if [ -n "$join_round" ]; then
        check_equal "GroupChat: currentRound matches core Join" "$join_round" "$actual_round"
        [ $? -ne 0 ] && ((failed_checks++))
    else
        echo -e "\033[31m✗\033[0m Core Join: currentRound"
        echo -e "  currentRound() reverted; deployment cannot prove round alignment"
        ((failed_checks++))
    fi
else
    echo -e "\033[31m✗\033[0m GroupChat: currentRound"
    echo -e "  currentRound() reverted; current block may be before originBlocks"
    ((failed_checks++))
fi
echo ""

echo "Verifying GroupAdmin configuration..."
check_equal "GroupAdmin: GROUP_DEFAULTS_ADDRESS" "$GROUP_DEFAULTS_ADDRESS" "$(cast_call "$GROUP_ADMIN_ADDRESS" "GROUP_DEFAULTS_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GroupAdmin: GROUP_DELEGATE_ADDRESS" "$GROUP_DELEGATE_ADDRESS" "$(cast_call "$GROUP_ADMIN_ADDRESS" "GROUP_DELEGATE_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GroupAdmin: GROUP_ADDRESS" "$GROUP_ADDRESS" "$(cast_call "$GROUP_ADMIN_ADDRESS" "GROUP_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GroupAdmin: MAX_ADMIN_IDS" "$GROUP_CHAT_MAX_ADMIN_IDS" "$(cast_call "$GROUP_ADMIN_ADDRESS" "MAX_ADMIN_IDS()(uint256)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

echo "Verifying GroupBanList configuration..."
check_equal "GroupBanList: GROUP_ADMIN_ADDRESS" "$GROUP_ADMIN_ADDRESS" "$(cast_call "$GROUP_BAN_LIST_ADDRESS" "GROUP_ADMIN_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

echo "Verifying AdminBanSource configuration..."
check_equal "AdminBanSource: GROUP_BAN_LIST_ADDRESS" "$GROUP_BAN_LIST_ADDRESS" "$(cast_call "$ADMIN_BAN_SOURCE_ADDRESS" "GROUP_BAN_LIST_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

echo "Verifying GovVotedBanSource configuration..."
check_equal "GovVotedBanSource: GROUP_ADDRESS" "$GROUP_ADDRESS" "$(cast_call "$govVotedBanSourceAddress" "GROUP_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GovVotedBanSource: PRECISION" "1000000000000000000" "$(cast_call "$govVotedBanSourceAddress" "PRECISION()(uint256)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GovVotedBanSource: MIN_SUPPORT_TO_OPPOSE_RATIO" "$GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO" "$(cast_call "$govVotedBanSourceAddress" "MIN_SUPPORT_TO_OPPOSE_RATIO()(uint256)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GovVotedBanSource: BAN_THRESHOLD_RATIO" "$GROUP_CHAT_BAN_THRESHOLD_RATIO" "$(cast_call "$govVotedBanSourceAddress" "BAN_THRESHOLD_RATIO()(uint256)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

echo "Verifying GroupMember configuration..."
check_equal "GroupMember: GROUP_ADMIN_ADDRESS" "$GROUP_ADMIN_ADDRESS" "$(cast_call "$GROUP_MEMBER_ADDRESS" "GROUP_ADMIN_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GroupMember: GROUP_ADDRESS" "$GROUP_ADDRESS" "$(cast_call "$GROUP_MEMBER_ADDRESS" "GROUP_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

echo "Verifying GroupMemberScope configuration..."
check_equal "GroupMemberScope: GROUP_MEMBER_ADDRESS" "$GROUP_MEMBER_ADDRESS" "$(cast_call "$GROUP_MEMBER_SCOPE_ADDRESS" "GROUP_MEMBER_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

echo "Verifying GroupJoinScopeSource configuration..."
check_equal "GroupJoinScopeSource: GROUP_MEMBER_ADDRESS" "$GROUP_MEMBER_ADDRESS" "$(cast_call "$GROUP_JOIN_SCOPE_SOURCE_ADDRESS" "GROUP_MEMBER_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
check_equal "GroupJoinScopeSource: GROUP_JOIN_ADDRESS" "$GROUP_JOIN_ADDRESS" "$(cast_call "$GROUP_JOIN_SCOPE_SOURCE_ADDRESS" "GROUP_JOIN_ADDRESS()(address)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

echo "Verifying ExtensionCenter values used by managers..."

check_contract_code "ExtensionCenter: EXTENSION_CENTER_ADDRESS has code" $EXTENSION_CENTER_ADDRESS
[ $? -ne 0 ] && ((failed_checks++))
check_contract_code "ExtensionCenter: launchAddress has code" $center_launch_address
[ $? -ne 0 ] && ((failed_checks++))
check_contract_code "ExtensionCenter: stakeAddress has code" $center_stake_address
[ $? -ne 0 ] && ((failed_checks++))
check_contract_code "ExtensionCenter: joinAddress has code" $center_join_address
[ $? -ne 0 ] && ((failed_checks++))
check_contract_code "ExtensionCenter: voteAddress has code" $center_vote_address
[ $? -ne 0 ] && ((failed_checks++))
echo -e "  STAKE_ADDRESS:  $center_stake_address"
echo -e "  LAUNCH_ADDRESS: $center_launch_address"
echo -e "  JOIN_ADDRESS:   $center_join_address"
echo -e "  VOTE_ADDRESS:   $center_vote_address"
echo ""

check_manager_common() {
    local manager_name=$1
    local manager_address=$2

    check_equal "$manager_name: GROUP_CHAT_ADDRESS" "$groupChatAddress" "$(cast_call "$manager_address" "GROUP_CHAT_ADDRESS()(address)")"
    [ $? -ne 0 ] && ((failed_checks++))

    check_equal "$manager_name: BAN_SOURCE_ADDRESS" "$govVotedBanSourceAddress" "$(cast_call "$manager_address" "BAN_SOURCE_ADDRESS()(address)")"
    [ $? -ne 0 ] && ((failed_checks++))

    check_equal "$manager_name: BEFORE_POST_PLUGIN_ADDRESS" "$GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS" "$(cast_call "$manager_address" "BEFORE_POST_PLUGIN_ADDRESS()(address)")"
    [ $? -ne 0 ] && ((failed_checks++))

    check_equal "$manager_name: AFTER_POST_PLUGIN_ADDRESS" "$GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS" "$(cast_call "$manager_address" "AFTER_POST_PLUGIN_ADDRESS()(address)")"
    [ $? -ne 0 ] && ((failed_checks++))

    check_equal "$manager_name: EXTENSION_CENTER_ADDRESS" "$EXTENSION_CENTER_ADDRESS" "$(cast_call "$manager_address" "EXTENSION_CENTER_ADDRESS()(address)")"
    [ $? -ne 0 ] && ((failed_checks++))
}

echo "Verifying manager immutable configuration..."

check_manager_common "TokenMainManager" $tokenMainManagerAddress
echo ""

check_manager_common "TokenGovManager" $tokenGovManagerAddress
echo ""

check_manager_common "TokenActionGovManager" $tokenActionGovManagerAddress
check_equal "TokenActionGovManager: RECENT_ROUNDS" "$GROUP_CHAT_ACTION_RECENT_ROUNDS" "$(cast_call "$tokenActionGovManagerAddress" "RECENT_ROUNDS()(uint256)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

check_manager_common "TokenActionMainManager" $tokenActionMainManagerAddress
check_equal "TokenActionMainManager: RECENT_ROUNDS" "$GROUP_CHAT_ACTION_RECENT_ROUNDS" "$(cast_call "$tokenActionMainManagerAddress" "RECENT_ROUNDS()(uint256)")"
[ $? -ne 0 ] && ((failed_checks++))
echo ""

echo "========================================="
if [ $failed_checks -eq 0 ]; then
    echo -e "\033[32m✓ All parameter checks passed\033[0m"
    echo "========================================="
    return 0
else
    echo -e "\033[31m✗ $failed_checks check(s) failed\033[0m"
    echo "========================================="
    return 1
fi
