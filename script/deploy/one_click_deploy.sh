#!/bin/bash

echo -e "\n[Step 1/4] Initializing environment..."
source 00_init.sh $1
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Failed to initialize environment"
    return 1
fi

echo -e "\n========================================="
echo -e "  One-Click Deploy GroupChat"
echo -e "  Network: $network"
echo -e "========================================="

echo -e "\n[Step 2/4] Deploying GroupChat..."
source 01_deploy_group_chat.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Deployment failed"
    return 1
fi

if [[ "$network" == thinkium70001* ]]; then
    echo -e "\n[Step 3/4] Verifying contract on explorer..."
    source 02_verify.sh
    if [ $? -ne 0 ]; then
        echo -e "\033[33mWarning:\033[0m Contract verification failed (deployment is still successful)"
    else
        echo -e "\033[32m✓\033[0m Contract verified successfully"
    fi
else
    echo -e "\n[Step 3/4] Skipping contract verification (not a thinkium network)"
fi

echo -e "\n[Step 4/4] Running deployment checks..."
source 99_check.sh
if [ $? -ne 0 ]; then
    echo -e "\033[31mError:\033[0m Deployment checks failed"
    return 1
fi

echo -e "\n========================================="
echo -e "\033[32m✓ Deployment completed successfully!\033[0m"
echo -e "========================================="
echo -e "GroupChat Address: $groupChatAddress"
echo -e "TokenMainManager Address: $tokenMainManagerAddress"
echo -e "TokenGovManager Address: $tokenGovManagerAddress"
echo -e "TokenActionGovManager Address: $tokenActionGovManagerAddress"
echo -e "TokenActionMainManager Address: $tokenActionMainManagerAddress"
echo -e "LOVE20 Group Address: $GROUP_ADDRESS"
echo -e "GroupDefaults Address: $GROUP_DEFAULTS_ADDRESS"
echo -e "ExtensionCenter Address: $EXTENSION_CENTER_ADDRESS"
echo -e "Max Admin Ids: $GROUP_CHAT_MAX_ADMIN_IDS"
echo -e "Network: $network"
echo -e "=========================================\n"
