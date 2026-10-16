#!/bin/bash

source ./lib.sh || return 1

if [ -z "$RPC_URL" ]; then
    echo -e "\033[31mError:\033[0m Environment not initialized. Please run 00_init.sh first."
    return 1
fi

echo "Deploying GroupChat contract..."

forge_script ../DeployGroupChat.s.sol:DeployGroupChat --sig "run()"

if [ $? -eq 0 ]; then
    load_env_file "$network_dir/address.group.chat.params" || return 1
    export GROUP_ADMIN_ADDRESS=$groupAdminAddress
    export GROUP_BAN_LIST_ADDRESS=$groupBanListAddress
    export ADMIN_BAN_SOURCE_ADDRESS=$adminBanSourceAddress
    export GROUP_MEMBER_ADDRESS=$groupMemberAddress
    export GROUP_MEMBER_SCOPE_ADDRESS=$groupMemberScopeAddress
    export GROUP_JOIN_SCOPE_SOURCE_ADDRESS=$groupJoinScopeSourceAddress
    echo -e "\033[32m✓\033[0m GroupChat deployed at: $groupChatAddress"
    echo -e "\033[32m✓\033[0m GroupAdmin deployed at: $groupAdminAddress"
    echo -e "\033[32m✓\033[0m GroupBanList deployed at: $groupBanListAddress"
    echo -e "\033[32m✓\033[0m AdminBanSource deployed at: $adminBanSourceAddress"
    echo -e "\033[32m✓\033[0m GovVotedBanSource deployed at: $govVotedBanSourceAddress"
    echo -e "\033[32m✓\033[0m GroupMember deployed at: $groupMemberAddress"
    echo -e "\033[32m✓\033[0m GroupMemberScope deployed at: $groupMemberScopeAddress"
    echo -e "\033[32m✓\033[0m GroupJoinScopeSource deployed at: $groupJoinScopeSourceAddress"
    echo -e "\033[32m✓\033[0m TokenMainManager deployed at: $tokenMainManagerAddress"
    echo -e "\033[32m✓\033[0m TokenGovManager deployed at: $tokenGovManagerAddress"
    echo -e "\033[32m✓\033[0m TokenActionGovManager deployed at: $tokenActionGovManagerAddress"
    echo -e "\033[32m✓\033[0m TokenActionMainManager deployed at: $tokenActionMainManagerAddress"
    return 0
else
    echo -e "\033[31m✗\033[0m Failed to deploy GroupChat"
    return 1
fi
