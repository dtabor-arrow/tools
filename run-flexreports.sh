#!/usr/bin/env bash

set -euo pipefail

# API key for authentication - can be set here or via environment variable
# Leave empty to prompt user at runtime

API_KEY=""

# Flag to control output verbosity
# Set to true with --quiet or -s flags to suppress status messages

QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-s)
      # Enable quiet mode - suppresses "is executing" and "Executed" messages
      QUIET=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Determine API key from environment, script, or user prompt
# Priority order:
#   1. Environment variable (CLOUDHEALTH_API_KEY)
#   2. Script variable (API_KEY set above)
#   3. User prompt (secure input with hidden characters)

if [[ -n "${CLOUDHEALTH_API_KEY:-}" ]]; then
  API_KEY="${CLOUDHEALTH_API_KEY}"
elif [[ -z "${API_KEY}" ]]; then
  read -p "Enter API key: " API_KEY
  echo
  if [[ -z "${API_KEY}" ]]; then
    echo "API key is required" >&2
    exit 1
  fi
fi

# Example list of reports to execute
# Each entry format: "Report Name,crn:account:flexreports/report-uuid"

# runlist=(
#	  "ANA Business Unit,crn:12345:flexreports/74b758fb-b38b-40ea-b8e7-601bba056eqq"
#	  "Shared VNet Daily,crn:12345:flexreports/61552b2d-910a-4f1d-b3da-53737c6f3aqq"
#	  "Shared VNet Monthly,crn:12345:flexreports/0a7a3073-db25-48f6-b3b1-6c84ee8a9cqq"
#	  "Azure Unused Reservations - Monthly,crn:12345:flexreports/abe13443-44fe-4a9a-93b9-8ea2195b52qq"
# )

# Active runlist - add your reports here

runlist=(

)

# Obtain access token from CloudHealth API

ACCESSTOKEN=$(
  curl -s 'https://apps.cloudhealthtech.com/graphql' \
    -H 'Accept-Encoding: gzip, deflate, br' \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H 'Connection: keep-alive' \
    --data-binary "{\"query\":\"mutation Login(\$apiKey:String!){loginAPI(apiKey:\$apiKey){accessToken}}\",\"variables\":{\"apiKey\":\"${API_KEY}\"}}" \
    --compressed | jq -r '.data.loginAPI.accessToken'
)

# Validate that we successfully obtained an access token

if [[ -z "${ACCESSTOKEN:-}" || "${ACCESSTOKEN}" == "null" ]]; then
  echo "Failed to obtain access token" >&2
  exit 1
fi

# Loop through array entries

for entry in "${runlist[@]}"; do
  IFS=',' read -r REPORTNAME REPORTID <<< "$entry"
  if [[ "$QUIET" == false ]]; then
    echo "${REPORTNAME} is executing"
  fi

# Execute the flex report via GraphQL mutation

  RESPONSE=$(curl -s "https://apps.cloudhealthtech.com/graphql" \
    -H "Accept-Encoding: gzip, deflate, br" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Connection: keep-alive" \
    -H "Authorization: Bearer ${ACCESSTOKEN}" \
    --data-binary "{\"query\":\"mutation executeFlexReport{triggerFlexReportExecution(id:\\\"${REPORTID}\\\")}\",\"variables\":{}}" \
    --compressed)

  # Check API response for success or failure
  if ! grep -q '"triggerFlexReportExecution":true' <<< "$RESPONSE"; then
    echo "Error executing ${REPORTNAME}: ${RESPONSE}" >&2
  elif [[ "$QUIET" == false ]]; then
    echo "> Executed ${REPORTNAME}"
    echo
  fi
done
