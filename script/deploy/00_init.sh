# ------ set network ------
export network="$1"
if [ -z "$network" ] || [ ! -d "../network/$network" ]; then
    echo -e "\033[31mError:\033[0m Network parameter is required."
    echo -e "\nAvailable networks:"
    for net in $(ls ../network); do
        echo "  - $net"
    done
    return 1
fi

echo -e "Selected network: \033[36m$network\033[0m"

# ------ dont change below ------
source ./lib.sh || return 1

network_dir="../network/$network"

if [ ! -f "$network_dir/.account" ]; then
    echo -e "\033[31mError:\033[0m .account file not found"
    echo -e "Please create $network_dir/.account with KEYSTORE_ACCOUNT and ACCOUNT_ADDRESS"
    echo -e "You can start from $network_dir/.account.example"
    return 1
fi
load_env_file "$network_dir/.account" || return 1
load_env_file "$network_dir/network.params" || return 1

if [ -f "$network_dir/address.group.params" ]; then
    load_env_file "$network_dir/address.group.params" || return 1
fi

if [ -f "$network_dir/address.group.chat.params" ]; then
    load_env_file "$network_dir/address.group.chat.params" || return 1
fi

if [ -f "$network_dir/address.group.defaults.params" ]; then
    load_env_file "$network_dir/address.group.defaults.params" || return 1
fi

if [ -f "$network_dir/address.group.delegate.params" ]; then
    load_env_file "$network_dir/address.group.delegate.params" || return 1
fi

if [ -f "$network_dir/group.chat.params" ]; then
    load_env_file "$network_dir/group.chat.params" || return 1
    unset ORIGIN_BLOCKS
    unset PHASE_BLOCKS

    if [ -n "$groupAddress" ]; then
        export GROUP_ADDRESS=$groupAddress
    fi

    if [ -n "$groupDefaultsAddress" ]; then
        export GROUP_DEFAULTS_ADDRESS=$groupDefaultsAddress
    fi

    if [ -n "$groupDelegateAddress" ]; then
        export GROUP_DELEGATE_ADDRESS=$groupDelegateAddress
    fi

    if [ -n "$extensionCenterAddress" ]; then
        export EXTENSION_CENTER_ADDRESS=$extensionCenterAddress
    fi

    if [ -n "$groupJoinAddress" ]; then
        export GROUP_JOIN_ADDRESS=$groupJoinAddress
    fi

    if [ -n "$groupAdminAddress" ]; then
        export GROUP_ADMIN_ADDRESS=$groupAdminAddress
    fi

    if [ -n "$groupBanListAddress" ]; then
        export GROUP_BAN_LIST_ADDRESS=$groupBanListAddress
    fi

    if [ -n "$groupMemberAddress" ]; then
        export GROUP_MEMBER_ADDRESS=$groupMemberAddress
    fi

    if [ -n "$groupMemberScopeAddress" ]; then
        export GROUP_MEMBER_SCOPE_ADDRESS=$groupMemberScopeAddress
    fi

    if [ -n "$groupJoinScopeSourceAddress" ]; then
        export GROUP_JOIN_SCOPE_SOURCE_ADDRESS=$groupJoinScopeSourceAddress
    fi

    if [ -n "$adminBanSourceAddress" ]; then
        export ADMIN_BAN_SOURCE_ADDRESS=$adminBanSourceAddress
    fi

    if [ -n "$groupChatBeforePostPluginAddress" ]; then
        export GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS=$groupChatBeforePostPluginAddress
    fi

    if [ -n "$groupChatAfterPostPluginAddress" ]; then
        export GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS=$groupChatAfterPostPluginAddress
    fi

    if [ -n "$actionRecentRounds" ]; then
        export GROUP_CHAT_ACTION_RECENT_ROUNDS=$actionRecentRounds
    fi

    if [ -n "$maxContentLength" ]; then
        export GROUP_CHAT_MAX_CONTENT_LENGTH=$maxContentLength
    fi

    if [ -n "$maxMentionedSenderIds" ]; then
        export GROUP_CHAT_MAX_MENTIONED_SENDER_IDS=$maxMentionedSenderIds
    fi

    if [ -n "$banThresholdRatio" ]; then
        export GROUP_CHAT_BAN_THRESHOLD_RATIO=$banThresholdRatio
    fi

    if [ -n "$minSupportToOpposeRatio" ]; then
        export GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO=$minSupportToOpposeRatio
    fi

    if [ -n "$maxAdminIds" ]; then
        export GROUP_CHAT_MAX_ADMIN_IDS=$maxAdminIds
    fi

    if [ -z "$GROUP_DEFAULTS_ADDRESS" ]; then
        echo -e "\033[31mError:\033[0m GROUP_DEFAULTS_ADDRESS not set"
        echo -e "Please provide groupDefaultsAddress in $network_dir/address.group.defaults.params"
        return 1
    fi

    if [ -z "$GROUP_DELEGATE_ADDRESS" ]; then
        echo -e "\033[31mError:\033[0m GROUP_DELEGATE_ADDRESS not set"
        echo -e "Please provide groupDelegateAddress in $network_dir/address.group.delegate.params"
        return 1
    fi

    if [ -z "$EXTENSION_CENTER_ADDRESS" ]; then
        echo -e "\033[31mError:\033[0m EXTENSION_CENTER_ADDRESS not set"
        echo -e "Please provide extensionCenterAddress in $network_dir/group.chat.params"
        return 1
    fi

    if [ -z "$GROUP_JOIN_ADDRESS" ]; then
        echo -e "\033[31mError:\033[0m GROUP_JOIN_ADDRESS not set"
        echo -e "Please provide groupJoinAddress in $network_dir/group.chat.params"
        return 1
    fi

    if [ -z "$GROUP_CHAT_ACTION_RECENT_ROUNDS" ]; then
        echo -e "\033[31mError:\033[0m GROUP_CHAT_ACTION_RECENT_ROUNDS not set"
        echo -e "Please provide actionRecentRounds in $network_dir/group.chat.params"
        return 1
    fi

    if [ -z "$GROUP_CHAT_BAN_THRESHOLD_RATIO" ]; then
        export GROUP_CHAT_BAN_THRESHOLD_RATIO=3000000000000000
    fi

    if [ -z "$GROUP_CHAT_MAX_CONTENT_LENGTH" ]; then
        export GROUP_CHAT_MAX_CONTENT_LENGTH=4096
    fi

    if [ -z "$GROUP_CHAT_MAX_MENTIONED_SENDER_IDS" ]; then
        export GROUP_CHAT_MAX_MENTIONED_SENDER_IDS=32
    fi

    if [ -z "$GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO" ]; then
        export GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO=10
    fi

    if [ -z "$GROUP_CHAT_MAX_ADMIN_IDS" ]; then
        export GROUP_CHAT_MAX_ADMIN_IDS=20
    fi

    zero_address=0x0000000000000000000000000000000000000000

    if [ -z "$GROUP_ADMIN_ADDRESS" ]; then
        export GROUP_ADMIN_ADDRESS=""
    fi

    if [ -z "$GROUP_BAN_LIST_ADDRESS" ]; then
        export GROUP_BAN_LIST_ADDRESS=""
    fi

    if [ -z "$GROUP_MEMBER_SCOPE_ADDRESS" ]; then
        export GROUP_MEMBER_SCOPE_ADDRESS=""
    fi

    if [ -z "$GROUP_MEMBER_ADDRESS" ]; then
        export GROUP_MEMBER_ADDRESS=""
    fi

    if [ -z "$GROUP_JOIN_SCOPE_SOURCE_ADDRESS" ]; then
        export GROUP_JOIN_SCOPE_SOURCE_ADDRESS=""
    fi

    if [ -z "$ADMIN_BAN_SOURCE_ADDRESS" ]; then
        export ADMIN_BAN_SOURCE_ADDRESS=""
    fi

    if [ -z "$GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS" ]; then
        export GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS=$zero_address
    fi

    if [ -z "$GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS" ]; then
        export GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS=$zero_address
    fi

    export GROUP_ADDRESS
    export GROUP_DEFAULTS_ADDRESS
    export GROUP_DELEGATE_ADDRESS
    export EXTENSION_CENTER_ADDRESS
    export GROUP_JOIN_ADDRESS
    export GROUP_ADMIN_ADDRESS
    export GROUP_BAN_LIST_ADDRESS
    export GROUP_MEMBER_ADDRESS
    export GROUP_MEMBER_SCOPE_ADDRESS
    export GROUP_JOIN_SCOPE_SOURCE_ADDRESS
    export ADMIN_BAN_SOURCE_ADDRESS
    export GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS
    export GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS
    export GROUP_CHAT_ACTION_RECENT_ROUNDS
    export GROUP_CHAT_MAX_CONTENT_LENGTH
    export GROUP_CHAT_MAX_MENTIONED_SENDER_IDS
    export GROUP_CHAT_BAN_THRESHOLD_RATIO
    export GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO
    export GROUP_CHAT_MAX_ADMIN_IDS

    echo "GroupChat Configuration loaded:"
    if [ -n "$GROUP_ADDRESS" ]; then
        echo "  LOVE20 Group: $GROUP_ADDRESS"
    fi
    echo "  GroupDefaults: $GROUP_DEFAULTS_ADDRESS"
    echo "  GroupDelegate: $GROUP_DELEGATE_ADDRESS"
    echo "  ExtensionCenter: $EXTENSION_CENTER_ADDRESS"
    echo "  GroupJoin: $GROUP_JOIN_ADDRESS"
    echo "  GroupAdmin: $GROUP_ADMIN_ADDRESS"
    echo "  GroupBanList: $GROUP_BAN_LIST_ADDRESS"
    echo "  GroupMember: $GROUP_MEMBER_ADDRESS"
    echo "  GroupMemberScope: $GROUP_MEMBER_SCOPE_ADDRESS"
    echo "  GroupJoinScopeSource: $GROUP_JOIN_SCOPE_SOURCE_ADDRESS"
    echo "  AdminBanSource: $ADMIN_BAN_SOURCE_ADDRESS"
    echo "  GovVotedBanSource: $govVotedBanSourceAddress"
    echo "  BeforePostPlugin: $GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS"
    echo "  AfterPostPlugin: $GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS"
    echo "  ActionRecentRounds: $GROUP_CHAT_ACTION_RECENT_ROUNDS"
    echo "  MaxContentLength: $GROUP_CHAT_MAX_CONTENT_LENGTH"
    echo "  MaxMentionedSenderIds: $GROUP_CHAT_MAX_MENTIONED_SENDER_IDS"
    echo "  MinSupportToOpposeRatio: $GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_RATIO"
    echo "  BanThresholdRatio: $GROUP_CHAT_BAN_THRESHOLD_RATIO"
    echo "  MaxAdminIds: $GROUP_CHAT_MAX_ADMIN_IDS"
    echo "  RoundSource: ExtensionCenter.joinAddress().originBlocks/phaseBlocks"
else
    echo -e "\033[31mError:\033[0m group.chat.params not found"
    echo -e "Please create $network_dir/group.chat.params"
    return 1
fi

if [ "$network" = "anvil" ]; then
    if [ -z "$PRIVATE_KEY" ]; then
        echo -e "\033[31mError:\033[0m PRIVATE_KEY is required for anvil deployment."
        return 1
    fi
    export KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:-}"
    export KEYSTORE_PASSWORD_ACCOUNT="$KEYSTORE_ACCOUNT"
    echo "Using PRIVATE_KEY from anvil .account"
elif [ -z "$KEYSTORE_PASSWORD" ]; then
    echo -e "\nPlease enter keystore password (for $KEYSTORE_ACCOUNT):"
    read -s KEYSTORE_PASSWORD
    export KEYSTORE_PASSWORD
    echo "Password saved, will not be requested again in this session"
else
    echo -e "\nUsing KEYSTORE_PASSWORD from environment"
fi

cast_call() {
    local address=$1
    local function_signature=$2
    shift 2
    local args=("$@")

    cast call "$address" \
        "$function_signature" \
        "${args[@]}" \
        --rpc-url "$RPC_URL"
}
echo "cast_call() loaded"

check_equal() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    expected=$(normalize_cast_value "$expected")
    actual=$(normalize_cast_value "$actual")
    expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')
    actual=$(echo "$actual" | tr '[:upper:]' '[:lower:]')

    if [ "$expected" = "$actual" ]; then
        echo -e "\033[32m✓\033[0m $description"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        return 0
    else
        echo -e "\033[31m✗\033[0m $description"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        return 1
    fi
}
echo "check_equal() loaded"

normalize_cast_value() {
    local value="$1"

    value=$(trim_whitespace "$value")
    case "$value" in
        *" ["*"]")
            value="${value%% \[*}"
            ;;
    esac

    printf '%s' "$value"
}

forge_script() {
  local verify_args=()

  if [[ "$network" != "anvil" && "$network" != thinkium* ]]; then
    verify_args=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
  fi

  if [ "$network" = "anvil" ]; then
    local anvil_build_args=()
    [ -n "$ANVIL_FOUNDRY_OUT" ] && anvil_build_args+=(--out "$ANVIL_FOUNDRY_OUT")
    [ -n "$ANVIL_FOUNDRY_CACHE" ] && anvil_build_args+=(--cache-path "$ANVIL_FOUNDRY_CACHE")

    forge script "$@" \
      --rpc-url "$RPC_URL" \
      --private-key "$PRIVATE_KEY" \
      --sender "$ACCOUNT_ADDRESS" \
      --gas-price 5000000000 \
      --gas-limit 50000000 \
      --broadcast \
      --legacy \
      "${anvil_build_args[@]}"
  else
    forge script "$@" \
      --rpc-url "$RPC_URL" \
      --account "$KEYSTORE_ACCOUNT" \
      --sender "$ACCOUNT_ADDRESS" \
      --password "$KEYSTORE_PASSWORD" \
      --gas-price 5000000000 \
      --gas-limit 50000000 \
      --broadcast \
      --legacy \
      "${verify_args[@]}"
  fi
}
echo "forge_script() loaded"
