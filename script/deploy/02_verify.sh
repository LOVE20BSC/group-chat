#!/bin/bash

source ./lib.sh || return 1

if [ -z "$network" ]; then
  echo -e "\033[31mError:\033[0m Environment not initialized. Please run 00_init.sh first."
  return 1
fi

if [[ "$network" != thinkium70001* ]]; then
  echo "Network is not thinkium70001 related, skipping verification"
  return 0
fi

if [ -z "$RPC_URL" ]; then
    source 00_init.sh "$network" || return 1
fi

if [ -f "$network_dir/address.group.chat.params" ] && { \
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

verify_contract(){
  local contract_address=$1
  local contract_name=$2
  local contract_path=$3

  echo "Verifying contract: $contract_name at $contract_address"

  forge verify-contract \
    --chain-id "$CHAIN_ID" \
    --verifier "$VERIFIER" \
    --verifier-url "$VERIFIER_URL" \
    "$contract_address" \
    "$contract_path:$contract_name"

  if [ $? -eq 0 ]; then
    echo -e "\033[32m✓\033[0m Contract $contract_name verified successfully"
    return 0
  else
    echo -e "\033[31m✗\033[0m Failed to verify contract $contract_name"
    return 1
  fi
}
echo "verify_contract() loaded"

failed_verifications=0

verify_contract "$groupChatAddress" "GroupChat" "src/GroupChat.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$groupAdminAddress" \
    "GroupAdmin" \
    "src/GroupAdmin.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$groupBanListAddress" \
    "GroupBanList" \
    "src/GroupBanList.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$adminBanSourceAddress" \
    "AdminBanSource" \
    "src/sources/ban/AdminBanSource.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$govVotedBanSourceAddress" \
    "GovVotedBanSource" \
    "src/sources/ban/GovVotedBanSource.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$groupMemberAddress" \
    "GroupMember" \
    "src/GroupMember.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$groupMemberScopeAddress" \
    "GroupMemberScope" \
    "src/sources/scope/GroupMemberScope.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$groupJoinScopeSourceAddress" \
    "GroupJoinScopeSource" \
    "src/sources/scope/GroupJoinScopeSource.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$tokenMainManagerAddress" \
    "TokenMainManager" \
    "src/managers/TokenMainManager.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$tokenGovManagerAddress" \
    "TokenGovManager" \
    "src/managers/TokenGovManager.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$tokenActionGovManagerAddress" \
    "TokenActionGovManager" \
    "src/managers/TokenActionGovManager.sol"
[ $? -ne 0 ] && ((failed_verifications++))

verify_contract \
    "$tokenActionMainManagerAddress" \
    "TokenActionMainManager" \
    "src/managers/TokenActionMainManager.sol"
[ $? -ne 0 ] && ((failed_verifications++))

if [ $failed_verifications -gt 0 ]; then
    return 1
fi
