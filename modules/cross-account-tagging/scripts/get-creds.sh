#!/usr/bin/env bash
set -e

# shellcheck disable=SC2207
CREDENTIALS=($(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "terraform-aws-networking" \
  --query "[Credentials.AccessKeyId,Credentials.SecretAccessKey,Credentials.SessionToken]" \
  --output text))

unset AWS_PROFILE
export AWS_ACCESS_KEY_ID="${CREDENTIALS[0]}"
export AWS_SECRET_ACCESS_KEY="${CREDENTIALS[1]}"
export AWS_SESSION_TOKEN="${CREDENTIALS[2]}"
