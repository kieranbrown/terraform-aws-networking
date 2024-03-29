#!/usr/bin/env bash
set -e

for ROLE_ARN in ${ASSUME_ROLE}; do
  ROLE_ARN=${ROLE_ARN} source "${SCRIPT_DIR}/get-creds.sh"
done

# shellcheck disable=SC2086
aws ec2 create-tags \
  --resources "${RESOURCE_ID}" \
  --tags ${TAGS}
