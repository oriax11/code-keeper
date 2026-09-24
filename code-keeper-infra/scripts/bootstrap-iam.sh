#!/usr/bin/env bash
#
# bootstrap-iam.sh — create the IAM user Terraform uses to deploy Cloud-Design.
#
# Run this with an identity that already has IAM admin rights (e.g. AWS
# CloudShell, which is signed in as your console user). It creates a
# programmatic-only user, attaches permissions, and prints a new access key.
#
# Usage:
#   ./bootstrap-iam.sh [USER_NAME]
#   POLICY_MODE=scoped ./bootstrap-iam.sh [USER_NAME]
#   ./bootstrap-iam.sh --cleanup [USER_NAME]
#
# POLICY_MODE:
#   admin  (default) attach the managed AdministratorAccess policy
#   scoped           create + attach a least-privilege policy for this project
#
# The secret access key is printed once. Store it in ~/.aws/credentials
# (chmod 600) or a secret manager, and delete the key when you are done.
#
set -euo pipefail

USER_NAME="${1:-cloud-design-deployer}"
POLICY_MODE="${POLICY_MODE:-admin}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_POLICY_NAME="cloud-design-deployer-policy"

die() { echo "ERROR: $*" >&2; exit 1; }

require_aws() {
  command -v aws >/dev/null 2>&1 || die "aws CLI not found in PATH"
}

caller_account() {
  aws sts get-caller-identity --query Account --output text
}

show_identity() {
  echo "== Current caller =="
  aws sts get-caller-identity
  echo
}

cleanup() {
  local user="$1"
  echo "== Cleaning up IAM user: $user =="
  local key_ids
  key_ids=$(aws iam list-access-keys --user-name "$user" \
    --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || true)
  for k in $key_ids; do
    echo "Deleting access key: $k"
    aws iam delete-access-key --user-name "$user" --access-key-id "$k"
  done

  local policies
  policies=$(aws iam list-attached-user-policies --user-name "$user" \
    --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
  for p in $policies; do
    echo "Detaching policy: $p"
    aws iam detach-user-policy --user-name "$user" --policy-arn "$p"
  done

  # Remove the project-scoped policy if we created it.
  local account
  account=$(caller_account)
  if aws iam get-policy \
      --policy-arn "arn:aws:iam::${account}:policy/${PROJECT_POLICY_NAME}" >/dev/null 2>&1; then
    echo "Deleting project policy: ${PROJECT_POLICY_NAME}"
    aws iam delete-policy \
      --policy-arn "arn:aws:iam::${account}:policy/${PROJECT_POLICY_NAME}"
  fi

  echo "Deleting user: $user"
  aws iam delete-user --user-name "$user"
  echo "Done."
}

attach_scoped_policy() {
  local account="$1"
  local tmp_policy
  tmp_policy="$(mktemp)"
  cat > "$tmp_policy" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CoreServices",
      "Effect": "Allow",
      "Action": [
        "ec2:*", "ecs:*", "efs:*", "elasticloadbalancing:*",
        "servicediscovery:*", "application-autoscaling:*",
        "logs:*", "cloudwatch:*", "secretsmanager:*",
        "acm:*", "cognito-idp:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IamForTerraform",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy",
        "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies", "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile", "iam:GetInstanceProfile",
        "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
        "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:TagRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Bootstrap",
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*"
    }
  ]
}
JSON

  local policy_arn="arn:aws:iam::${account}:policy/${PROJECT_POLICY_NAME}"
  if ! aws iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
    echo "Creating project policy: ${PROJECT_POLICY_NAME}"
    aws iam create-policy \
      --policy-name "$PROJECT_POLICY_NAME" \
      --policy-document "file://${tmp_policy}" >/dev/null
  fi
  rm -f "$tmp_policy"

  aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$policy_arn"
  echo "Attached scoped policy: $policy_arn"
}

main() {
  require_aws
  show_identity
  local account
  account=$(caller_account)

  if ! aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
    echo "Creating user: $USER_NAME"
    aws iam create-user --user-name "$USER_NAME" >/dev/null
  else
    echo "User already exists: $USER_NAME"
  fi

  case "$POLICY_MODE" in
    admin)
      aws iam attach-user-policy \
        --user-name "$USER_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
      echo "Attached AdministratorAccess"
      ;;
    scoped)
      attach_scoped_policy "$account"
      ;;
    *)
      die "unknown POLICY_MODE '$POLICY_MODE' (use admin or scoped)"
      ;;
  esac

  echo
  echo "== Creating access key (secret shown only once) =="
  aws iam create-access-key --user-name "$USER_NAME" \
    --query 'AccessKey.{id:AccessKeyId,secret:SecretAccessKey}' --output text \
    | awk '{printf "aws_access_key_id = %s\naws_secret_access_key = %s\n", $1, $2}'

  echo
  echo "Store the two lines above in ~/.aws/credentials under [default], set region = ${AWS_REGION},"
  echo "then: chmod 600 ~/.aws/credentials"
  echo
  echo "Verify with: aws sts get-caller-identity"
  echo "Cleanup with: $0 --cleanup $USER_NAME"
}

if [[ "${1:-}" == "--cleanup" ]]; then
  require_aws
  cleanup "${2:-cloud-design-deployer}"
else
  main
fi
