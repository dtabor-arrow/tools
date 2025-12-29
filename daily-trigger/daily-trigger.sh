#!/usr/local/bin/bash
# Last modified: 29-Dec-2025 09:26
#
# Script: daily-trigger.sh
# Description: Triggers CloudHealth FlexReports based on report list
#
# This script authenticates with CloudHealth via GraphQL API and executes
# FlexReports listed in daily-list.txt. The report list should contain one
# report per line in CSV format: "Report Name,report_id"
#
# Usage: ./daily-trigger.sh [options]
#        CLOUDHEALTH_API_KEY=your_key ./daily-trigger.sh
#
# Options:
#   -h, --help    Display this help message and exit
#
# Prerequisites:
#   - curl (for API requests)
#   - jq (for JSON parsing)
#   - daily-list.txt (report list file in current directory)
#
# Environment Variables:
#   CLOUDHEALTH_API_KEY    Optional. CloudHealth API key for authentication.
#                          If not set, script will prompt interactively.
#
# Report List Format (daily-list.txt):
#   Report Name,crn:12345:flexreports/uuid
#   Example: Azure Daily Cost,crn:24247:flexreports/88652125-cf1e-431e-b5df-fa62fab218ab
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Constants
readonly GRAPHQL_ENDPOINT="https://apps.cloudhealthtech.com/graphql"
readonly REPORT_LIST_FILE="daily-list.txt"

# Function: show_usage
# Display help information and usage instructions
show_usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Triggers CloudHealth FlexReports from daily-list.txt

Options:
  -h, --help    Display this help message and exit

Prerequisites:
  - curl (for API requests)
  - jq (for JSON parsing)
  - daily-list.txt (report list in current directory)

Environment Variables:
  CLOUDHEALTH_API_KEY    CloudHealth API key (optional, will prompt if not set)

Report List Format:
  The daily-list.txt file should contain one report per line in CSV format:
  Report Name,crn:12345:flexreports/uuid

  Example:
  Azure Daily Cost,crn:24247:flexreports/88652125-cf1e-431e-b5df-fa62fab218ab

Usage Examples:
  # Interactive mode (prompts for API key)
  ./daily-trigger.sh

  # Using environment variable
  CLOUDHEALTH_API_KEY=your_api_key ./daily-trigger.sh

  # Display help
  ./daily-trigger.sh --help

EOF
}

# Function: check_dependencies
# Verify that required tools and files are available
check_dependencies() {
    local missing_deps=0

    # Check for curl
    if ! command -v curl &> /dev/null; then
        echo "ERROR: curl is not installed. Please install curl and try again." >&2
        missing_deps=1
    fi

    # Check for jq
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq is not installed. Please install jq and try again." >&2
        missing_deps=1
    fi

    # Check for report list file
    if [[ ! -f "$REPORT_LIST_FILE" ]]; then
        echo "ERROR: Report list file '$REPORT_LIST_FILE' not found." >&2
        echo "Please create the file in the current directory with the required format." >&2
        missing_deps=1
    elif [[ ! -r "$REPORT_LIST_FILE" ]]; then
        echo "ERROR: Report list file '$REPORT_LIST_FILE' is not readable." >&2
        missing_deps=1
    fi

    # Exit if any dependencies are missing
    if [[ $missing_deps -eq 1 ]]; then
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Main Script Execution
#------------------------------------------------------------------------------

# Parse command line arguments for help flag
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    show_usage
    exit 0
fi

# Verify all dependencies are available before proceeding
check_dependencies

# Get API key from environment variable or prompt user
if [[ -n "${CLOUDHEALTH_API_KEY:-}" ]]; then
    API_KEY="$CLOUDHEALTH_API_KEY"
    echo "Using API key from CLOUDHEALTH_API_KEY environment variable"
else
    read -p "CloudHealth API key: " API_KEY
fi

# Validate that API key is not empty
if [[ -z "$API_KEY" ]]; then
    echo "ERROR: API key cannot be empty" >&2
    exit 1
fi

#------------------------------------------------------------------------------
# Authentication: Get Access Token via GraphQL
#------------------------------------------------------------------------------

echo "Authenticating with CloudHealth..."

# Execute GraphQL mutation to authenticate and obtain access token
# The mutation takes the API key and returns an access token for subsequent requests
ACCESSTOKEN=$(curl -s "$GRAPHQL_ENDPOINT" \
    -H 'Accept-Encoding: gzip, deflate, br' \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H 'Connection: keep-alive' \
    --data-binary "{\"query\":\"mutation Login(\$apiKey:String!){loginAPI(apiKey:\$apiKey){accessToken}}\",\"variables\":{\"apiKey\":\"$API_KEY\"}}" \
    --compressed | jq -r '.data.loginAPI.accessToken')

# Validate that authentication was successful
if [[ -z "$ACCESSTOKEN" ]] || [[ "$ACCESSTOKEN" == "null" ]]; then
    echo "ERROR: Authentication failed. Please check your API key." >&2
    exit 1
fi

echo "Authentication successful"
echo ""

#------------------------------------------------------------------------------
# Report Execution: Process Each Report from List
#------------------------------------------------------------------------------

echo "Processing reports from $REPORT_LIST_FILE..."
echo ""

# Read the report list file line by line
# Each line contains: Report Name,Report ID (comma-separated)
# The IFS=',' splits each line on the comma into REPORTNAME and REPORTID
while IFS=',' read -r REPORTNAME REPORTID; do

    # Skip empty lines
    if [[ -z "$REPORTNAME" ]]; then
        continue
    fi

    echo "Executing: $REPORTNAME"

    # Execute GraphQL mutation to trigger the FlexReport
    # The mutation takes the report ID and triggers report execution
    curl -s "$GRAPHQL_ENDPOINT" \
        -H "Accept-Encoding: gzip, deflate, br" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "Connection: keep-alive" \
        -H "Authorization: Bearer $ACCESSTOKEN" \
        --data-binary "{\"query\":\"mutation executeFlexReport{triggerFlexReportExecution(id:\\\"$REPORTID\\\")}\",\"variables\":{}}" \
        --compressed > /dev/null

    echo ""

done < "$REPORT_LIST_FILE"

echo "All reports have been triggered successfully"
