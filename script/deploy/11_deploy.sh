#!/usr/bin/env bash
set -euo pipefail

# Step 1: deploy and initialize the contracts. Self-contained: loads and validates every file
# it needs, without relying on a preloaded caller environment.
# Usage: script/deploy/11_deploy.sh <network>
# This step writes addresses.group-chat.params, which 21_check.sh and 31_verify.sh load on their
# own.

network="${1:?usage: script/deploy/11_deploy.sh <network>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NETWORK_DIR="$PROJECT_ROOT/script/network/$network"

# Parameter file loader: 1e17 / 1_000_000 style literals are expanded to decimal on load (params.sh).
source "$SCRIPT_DIR/params.sh"

if [ ! -d "$NETWORK_DIR" ]; then
    echo "Error: Network directory not found: $NETWORK_DIR"
    exit 1
fi

# An abnormal previous exit may leave a hidden address temp file behind; only this module's temp
# pattern is removed, never the real address file.
rm -f "$NETWORK_DIR/.addresses.group-chat.params."*

# Required configuration: addresses.core.params / addresses.action.params hold the dependency's
# deployed addresses and are loaded in dependency order.
for config in network.params addresses.core.params addresses.action.params group-chat.params .account; do
    if [ ! -f "$NETWORK_DIR/$config" ]; then
        echo "Error: Missing required configuration: $NETWORK_DIR/$config"
        exit 1
    fi
done

# Parameters come from files only: clear every key the files define, so a value exported by the
# caller cannot override a file value. The two plugin slots are the keys whose absence would change
# behaviour silently (a misspelled or blanked key would deploy a group without plugins), so both are
# asserted against the file itself, never against the variable - an inherited value could satisfy
# that. An empty value is rejected too: "not mounted" must be spelled as the zero address.
params_require_values "$NETWORK_DIR/group-chat.params" \
    GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS || exit 1

params_unset_all "$NETWORK_DIR/network.params" "$NETWORK_DIR/addresses.core.params" \
    "$NETWORK_DIR/addresses.action.params" "$NETWORK_DIR/group-chat.params"

env_password="${KEYSTORE_PASSWORD:-}"
params_load "$NETWORK_DIR/network.params"
params_load "$NETWORK_DIR/addresses.core.params"
params_load "$NETWORK_DIR/addresses.action.params"
params_load "$NETWORK_DIR/group-chat.params"
# .account is plain-sourced: the password may contain "#" and must not go through parameter
# expansion.
set -a
source "$NETWORK_DIR/.account"
set +a

# An empty KEYSTORE_PASSWORD line in .account must not clear a password exported by the entrypoint
# (that would prompt a second time).
[ -n "${KEYSTORE_PASSWORD:-}" ] || KEYSTORE_PASSWORD="$env_password"

[ -n "${KEYSTORE_ACCOUNT:-}" ] && [ -n "${ACCOUNT_ADDRESS:-}" ] \
    || { echo "Error: KEYSTORE_ACCOUNT / ACCOUNT_ADDRESS is not set in $NETWORK_DIR/.account" >&2; exit 1; }

# Verify the actual chain; being able to reach the RPC is not enough.
ACTUAL_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL") || exit 1
if [ "$ACTUAL_CHAIN_ID" != "$CHAIN_ID" ]; then
    echo "Error: RPC chain ID $ACTUAL_CHAIN_ID does not match configured CHAIN_ID $CHAIN_ID"
    exit 1
fi

# Keystore password: no prompt when already set (non-interactive use), otherwise read via the macOS
# dialog.
if [ -z "${KEYSTORE_PASSWORD:-}" ]; then
    if ! command -v osascript >/dev/null 2>&1; then
        echo "Error: KEYSTORE_PASSWORD is empty and osascript is unavailable; set it in $NETWORK_DIR/.account for non-interactive use." >&2
        exit 1
    fi
    KEYSTORE_PASSWORD="$(osascript <<APPLESCRIPT
text returned of (display dialog "Enter keystore password for $KEYSTORE_ACCOUNT:" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK")
APPLESCRIPT
)"
fi

# The twelve addresses are extracted from the deployment log and validated one by one; any missing
# entry fails the step instead of writing a half-filled address file.
require_deployed_addresses() {
    local field
    for field in GROUP_ADMIN_ADDRESS GROUP_CHAT_ADDRESS \
        GROUP_CHAT_BAN_LIST_ADDRESS ADMIN_BAN_SOURCE_ADDRESS GOV_VOTED_BAN_SOURCE_ADDRESS \
        GROUP_MEMBER_ADDRESS GROUP_MEMBER_SCOPE_ADDRESS GROUP_JOIN_SCOPE_SOURCE_ADDRESS \
        TOKEN_MAIN_MANAGER_ADDRESS TOKEN_GOV_MANAGER_ADDRESS TOKEN_ACTION_GOV_MANAGER_ADDRESS \
        TOKEN_ACTION_MAIN_MANAGER_ADDRESS; do
        if [[ ! ${!field:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ ${!field:-} = 0x0000000000000000000000000000000000000000 ]]; then
            echo "Error: Missing or invalid $field extracted from deployment log"
            exit 1
        fi
    done
}

echo "=== Deploying GroupChat Contracts to $network ==="
echo "  RPC_URL: $RPC_URL"
echo "  CHAIN_ID: $CHAIN_ID"

# A failure after broadcast must leave both the log and the artifact path behind for manual
# recovery; a failure before broadcast only removes this run's temp files. The password goes to
# forge through a temp file because --password would put the plaintext into the process arguments
# (/proc/<pid>/cmdline is 0444, readable by every local user). The trap is installed before the
# password is written, so a failing chmod/printf leaks nothing.
DEPLOY_LOG=$(mktemp)
PASSWORD_FILE=$(mktemp)
ADDRESS_TMP="$NETWORK_DIR/.addresses.group-chat.params.$$"
DEPLOY_SAVED=0
DEPLOY_ATTEMPTED=0
trap 'rm -f "$ADDRESS_TMP" "$PASSWORD_FILE"
if [ "$DEPLOY_SAVED" = 1 ] || [ "$DEPLOY_ATTEMPTED" = 0 ]; then
    rm -f "$DEPLOY_LOG"
else
    echo "  Addresses were not saved; contracts may already be on chain." >&2
    echo "  Deployment log: $DEPLOY_LOG" >&2
    echo "  Broadcast artifact: $PROJECT_ROOT/broadcast/DeployGroupChat.s.sol/${CHAIN_ID:-unknown}/run-latest.json" >&2
fi' EXIT
chmod 600 "$PASSWORD_FILE"
printf '%s' "$KEYSTORE_PASSWORD" > "$PASSWORD_FILE"

cd "$PROJECT_ROOT"
DEPLOY_START_EPOCH_SECONDS=$(date +%s)
DEPLOY_ATTEMPTED=1
if ! { forge script script/deploy/DeployGroupChat.s.sol:DeployGroupChat \
    --sig "run()" \
    --rpc-url "$RPC_URL" \
    --chain-id "$CHAIN_ID" \
    --account "$KEYSTORE_ACCOUNT" \
    --sender "$ACCOUNT_ADDRESS" \
    --password-file "$PASSWORD_FILE" \
    --broadcast --slow -vvv 2>&1 | tee "$DEPLOY_LOG"; }; then
    echo "Error: Deployment failed; saved addresses were not changed."
    exit 1
fi
# The password is only needed for this forge call; delete it right after broadcast.
rm -f "$PASSWORD_FILE"

# Extract the addresses from the deployment output (_logDeploymentSummary in DeployGroupChat.s.sol).
# A non-matching grep would silently abort the pipeline under set -e, so every lookup tolerates
# failure and missing entries are reported by require_deployed_addresses.
for field in GROUP_ADMIN_ADDRESS GROUP_CHAT_ADDRESS \
    GROUP_CHAT_BAN_LIST_ADDRESS ADMIN_BAN_SOURCE_ADDRESS GOV_VOTED_BAN_SOURCE_ADDRESS \
    GROUP_MEMBER_ADDRESS GROUP_MEMBER_SCOPE_ADDRESS GROUP_JOIN_SCOPE_SOURCE_ADDRESS \
    TOKEN_MAIN_MANAGER_ADDRESS TOKEN_GOV_MANAGER_ADDRESS TOKEN_ACTION_GOV_MANAGER_ADDRESS \
    TOKEN_ACTION_MAIN_MANAGER_ADDRESS; do
    eval "$field=\$(grep \"$field=\" \"\$DEPLOY_LOG\" | tail -1 | cut -d'=' -f2 | xargs || true)"
done

require_deployed_addresses

BROADCAST_FILE="$PROJECT_ROOT/broadcast/DeployGroupChat.s.sol/$CHAIN_ID/run-latest.json"
if [ ! -f "$BROADCAST_FILE" ]; then
    echo "Error: Missing broadcast artifact: $BROADCAST_FILE"
    exit 1
fi
BROADCAST_TIMESTAMP_MS=$(sed -nE 's/.*"timestamp":[[:space:]]*([0-9]+).*/\1/p' "$BROADCAST_FILE" | tail -1)
if [ -z "$BROADCAST_TIMESTAMP_MS" ] || [ "$BROADCAST_TIMESTAMP_MS" -lt "$((DEPLOY_START_EPOCH_SECONDS * 1000))" ]; then
    echo "Error: Broadcast artifact was not updated by this deployment: $BROADCAST_FILE"
    exit 1
fi

cat > "$ADDRESS_TMP" <<EOFADDR
# Deployed addresses, written by script/deploy/11_deploy.sh. Do not edit by hand.
GROUP_ADMIN_ADDRESS=$GROUP_ADMIN_ADDRESS
GROUP_CHAT_ADDRESS=$GROUP_CHAT_ADDRESS
GROUP_CHAT_BAN_LIST_ADDRESS=$GROUP_CHAT_BAN_LIST_ADDRESS
ADMIN_BAN_SOURCE_ADDRESS=$ADMIN_BAN_SOURCE_ADDRESS
GOV_VOTED_BAN_SOURCE_ADDRESS=$GOV_VOTED_BAN_SOURCE_ADDRESS
GROUP_MEMBER_ADDRESS=$GROUP_MEMBER_ADDRESS
GROUP_MEMBER_SCOPE_ADDRESS=$GROUP_MEMBER_SCOPE_ADDRESS
GROUP_JOIN_SCOPE_SOURCE_ADDRESS=$GROUP_JOIN_SCOPE_SOURCE_ADDRESS
TOKEN_MAIN_MANAGER_ADDRESS=$TOKEN_MAIN_MANAGER_ADDRESS
TOKEN_GOV_MANAGER_ADDRESS=$TOKEN_GOV_MANAGER_ADDRESS
TOKEN_ACTION_GOV_MANAGER_ADDRESS=$TOKEN_ACTION_GOV_MANAGER_ADDRESS
TOKEN_ACTION_MAIN_MANAGER_ADDRESS=$TOKEN_ACTION_MAIN_MANAGER_ADDRESS
EOFADDR
mv "$ADDRESS_TMP" "$NETWORK_DIR/addresses.group-chat.params"

DEPLOY_SAVED=1
echo "✓ Deployment completed and addresses saved to $NETWORK_DIR/addresses.group-chat.params"
