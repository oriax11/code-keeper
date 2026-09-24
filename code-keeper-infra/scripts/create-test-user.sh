#!/usr/bin/env bash
#
# create-test-user.sh — create/confirm a Cognito test user and print an IdToken.
#
# The user pool and app client are discovered automatically (by pool name /
# first app client), so no arguments are required.
#
# Usage:
#   ./create-test-user.sh [username] [password]
#
# Overrides (environment variables):
#   USER_POOL_NAME   user pool name to look up   (default: cloud-design-user-pool)
#   POOL_ID          skip the pool lookup and use this pool id
#   CLIENT_ID        skip the client lookup and use this client id
#   TEST_USER        same as the first positional argument
#   TEST_PASSWORD    same as the second positional argument
#
# The password is generated if not supplied and always satisfies the pool policy
# (upper, lower, number, >= 8 chars).
#
set -euo pipefail

USER_POOL_NAME="${USER_POOL_NAME:-cloud-design-user-pool}"
POOL_ID="${POOL_ID:-}"
CLIENT_ID="${CLIENT_ID:-}"
TEST_USER="${TEST_USER:-${1:-testuser}}"
TEST_PASSWORD="${TEST_PASSWORD:-${2:-Cloud$(openssl rand -hex 4)X9}}"

# --- Discover the user pool id ---
if [ -z "$POOL_ID" ]; then
  POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 \
    --query "UserPools[?Name=='${USER_POOL_NAME}'].Id | [0]" --output text)
fi
if [ -z "$POOL_ID" ] || [ "$POOL_ID" = "None" ]; then
  echo "Error: Cognito user pool '${USER_POOL_NAME}' not found." >&2
  echo "Set POOL_ID=<id> to target a specific pool." >&2
  exit 1
fi

# --- Discover the app client id ---
if [ -z "$CLIENT_ID" ]; then
  CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id "$POOL_ID" \
    --query 'UserPoolClients[0].ClientId' --output text)
fi
if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "None" ]; then
  echo "Error: no app client found for pool ${POOL_ID}." >&2
  echo "Set CLIENT_ID=<id> to target a specific client." >&2
  exit 1
fi

echo "pool:   $POOL_ID"
echo "client: $CLIENT_ID"
echo

aws cognito-idp admin-create-user \
  --user-pool-id "$POOL_ID" \
  --username "$TEST_USER" \
  --message-action SUPPRESS \
  --user-attributes Name=email,Value=test@example.com Name=email_verified,Value=true \
  >/dev/null 2>&1 || true

aws cognito-idp admin-set-user-password \
  --user-pool-id "$POOL_ID" \
  --username "$TEST_USER" \
  --password "$TEST_PASSWORD" \
  --permanent

echo "username: $TEST_USER"
echo "password: $TEST_PASSWORD"
echo
echo "== IdToken =="
aws cognito-idp admin-initiate-auth \
  --user-pool-id "$POOL_ID" \
  --client-id "$CLIENT_ID" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters USERNAME="$TEST_USER",PASSWORD="$TEST_PASSWORD" \
  --query 'AuthenticationResult.IdToken' --output text
