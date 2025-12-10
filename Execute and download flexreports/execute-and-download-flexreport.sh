#!/usr/local/bin/bash

set -euo pipefail

# CloudHealth FlexReport Execution and Download Script
# Executes a FlexReport and downloads the resulting CSV file

# Display help message
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Executes a CloudHealth FlexReport and downloads the result as a CSV file.

OPTIONS:
    -h, --help    Display this help message and exit

REQUIREMENTS:
    - curl: For API requests
    - jq: For JSON parsing

USAGE:
    1. Run the script
    2. Enter your CloudHealth API key when prompted
    3. Enter the FlexReport ID when prompted
    4. Script will execute the report, poll for completion, and download the CSV

EOF
    exit 0
}

# Parse command line arguments
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    show_help
fi

# Check for required dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "ERROR: Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

# Validate that a variable is not empty
validate_not_empty() {
    local var_name="$1"
    local var_value="$2"

    if [[ -z "$var_value" ]] || [[ "$var_value" == "null" ]]; then
        echo "ERROR: Failed to retrieve $var_name from API response"
        exit 1
    fi
}

# Execute a GraphQL query
execute_graphql_query() {
    local query="$1"
    local auth_header="${2:-}"

    local response
    if [[ -n "$auth_header" ]]; then
        response=$(curl -s "https://apps.cloudhealthtech.com/graphql" \
            -H "Accept-Encoding: gzip, deflate, br" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -H "Connection: keep-alive" \
            -H "Origin: altair://-" \
            -H "Authorization: Bearer $auth_header" \
            --data-binary "$query" \
            --compressed)
    else
        response=$(curl -s "https://apps.cloudhealthtech.com/graphql" \
            -H "Accept-Encoding: gzip, deflate, br" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -H "Connection: keep-alive" \
            --data-binary "$query" \
            --compressed)
    fi

    if [[ $? -ne 0 ]]; then
        echo "ERROR: Network request failed"
        exit 1
    fi

    # Check for GraphQL errors
    local errors
    errors=$(echo "$response" | jq -r '.errors // empty')
    if [[ -n "$errors" ]]; then
        echo "ERROR: GraphQL query failed"
        echo "$errors" | jq -r '.[].message'
        exit 1
    fi

    echo "$response"
}

# Sanitize filename by removing/replacing problematic characters
sanitize_filename() {
    local filename="$1"
    # Replace spaces with underscores
    filename="${filename// /_}"
    # Remove or replace other problematic characters
    filename="${filename//[^a-zA-Z0-9._-]/_}"
    echo "$filename"
}

# Check dependencies before proceeding
check_dependencies

echo "=============================================="
echo "CloudHealth FlexReport Execution Tool"
echo "=============================================="
echo ""

# Prompt for API key (unmasked)
read -r -p "Enter your CloudHealth API key: " API_KEY

if [[ -z "$API_KEY" ]]; then
    echo "ERROR: API key cannot be empty"
    exit 1
fi

echo ""
echo "Authenticating with CloudHealth API..."

# Get GraphQL access token
login_query="{\"query\":\"mutation Login(\$apiKey:String!){loginAPI(apiKey:\$apiKey){accessToken}}\",\"variables\":{\"apiKey\":\"$API_KEY\"}}"
login_response=$(execute_graphql_query "$login_query")

ACCESSTOKEN=$(echo "$login_response" | jq -r '.data.loginAPI.accessToken')
validate_not_empty "access token" "$ACCESSTOKEN"

echo "Authentication successful"
echo ""

# Prompt for FlexReport ID
read -r -p "Enter FlexReport ID: " REPORTID

if [[ -z "$REPORTID" ]]; then
    echo "ERROR: FlexReport ID cannot be empty"
    exit 1
fi

echo ""

# Query report information
get_report_info() {
    local report_query="{\"query\":\"query queryReport{node(id:\\\"$REPORTID\\\"){id ... on FlexReport{name result{status reportUpdatedOn contents{preSignedUrl}}}}}\",\"variables\":{}}"
    execute_graphql_query "$report_query" "$ACCESSTOKEN"
}

# Get initial report information
REPORTINFO=$(get_report_info)

# Parse report name
REPORTNAME=$(echo "$REPORTINFO" | jq -r '.data.node.name')
validate_not_empty "report name" "$REPORTNAME"

echo "=============================================="
echo "EXECUTING REPORT: $REPORTNAME"
echo "=============================================="
echo ""

# Execute the FlexReport
execute_query="{\"query\":\"mutation executeFlexReport{triggerFlexReportExecution(id:\\\"$REPORTID\\\")}\",\"variables\":{}}"
execute_response=$(execute_graphql_query "$execute_query" "$ACCESSTOKEN")

echo "Report execution triggered successfully"
echo "Waiting 15 seconds before first status check..."
echo ""

sleep 15

# Initialize polling variables
COUNTER=1
SLEEP=10

# Poll for report completion
while true; do
    # Get current report information
    REPORTINFO=$(get_report_info)

    # Parse current status
    REPORTSTATUS=$(echo "$REPORTINFO" | jq -r '.data.node.result.status')
    validate_not_empty "report status" "$REPORTSTATUS"

    echo "Status check #$COUNTER: $REPORTSTATUS"

    # Check if report is completed
    if [[ "$REPORTSTATUS" == "COMPLETED" ]]; then
        echo ""
        echo "=============================================="
        echo "REPORT COMPLETED SUCCESSFULLY"
        echo "=============================================="
        break
    fi

    # Check if report is queued
    if [[ "$REPORTSTATUS" == "QUEUED" ]]; then
        echo ""
        echo "WARNING: Report is QUEUED"
        echo "This may indicate the report is waiting for resources."
        echo "Please check status in the CloudHealth platform."
        exit 1
    fi

    # Check if report failed
    if [[ "$REPORTSTATUS" == "FAILED" ]]; then
        echo ""
        echo "=============================================="
        echo "ERROR: REPORT EXECUTION FAILED"
        echo "=============================================="
        echo "Please check the report configuration in the CloudHealth platform."
        exit 1
    fi

    # Check retry limit
    if [[ $COUNTER -ge 5 ]]; then
        echo ""
        echo "=============================================="
        echo "TIMEOUT: Report still running after 5 checks"
        echo "=============================================="
        echo "The report is taking longer than expected."
        echo "Please check status in the CloudHealth platform."
        exit 1
    fi

    # Increment counter
    ((COUNTER++))

    # Exponential backoff: increase sleep time by 1.5x
    if [[ $COUNTER -gt 1 ]]; then
        SLEEP=$((SLEEP * 3 / 2))
    fi

    echo "Next status check in $SLEEP seconds..."
    echo ""
    sleep "$SLEEP"
done

# Download the report
echo ""
echo "Preparing to download report..."

# Get the download URL
REPORTURL=$(echo "$REPORTINFO" | jq -r '.data.node.result.contents[0].preSignedUrl')
validate_not_empty "download URL" "$REPORTURL"

# Sanitize the filename
DOWNLOADNAME=$(sanitize_filename "$REPORTNAME")

echo "Report Name: $REPORTNAME"
echo "Download URL: $REPORTURL"
echo "Saving as: ${DOWNLOADNAME}.csv"
echo ""

# Download the report
if curl -f -s "$REPORTURL" -o "${DOWNLOADNAME}.csv"; then
    echo "=============================================="
    echo "DOWNLOAD COMPLETE"
    echo "=============================================="
    echo "File saved: ${DOWNLOADNAME}.csv"
    echo ""

    # Show file size
    if [[ -f "${DOWNLOADNAME}.csv" ]]; then
        file_size=$(ls -lh "${DOWNLOADNAME}.csv" | awk '{print $5}')
        echo "File size: $file_size"
    fi
else
    echo ""
    echo "=============================================="
    echo "ERROR: DOWNLOAD FAILED"
    echo "=============================================="
    echo "Please try downloading manually from the CloudHealth platform."
    exit 1
fi

echo ""
