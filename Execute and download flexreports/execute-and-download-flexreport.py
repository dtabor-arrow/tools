#!/usr/bin/env python3

"""
CloudHealth FlexReport Execution and Download Script
Executes a FlexReport and downloads the resulting CSV file
"""

import sys
import json
import time
import re
import argparse
from pathlib import Path

# Check for required dependencies
try:
    import requests
except ImportError:
    print("ERROR: Missing required Python module 'requests'")
    print("Install with: pip install requests")
    sys.exit(1)


class CloudHealthFlexReport:
    """Handler for CloudHealth FlexReport operations"""

    def __init__(self, api_key):
        self.api_key = api_key
        self.access_token = None
        self.base_url = "https://apps.cloudhealthtech.com/graphql"
        self.headers = {
            "Accept-Encoding": "gzip, deflate, br",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Connection": "keep-alive",
            "Origin": "altair://-"
        }

    def authenticate(self):
        """Authenticate and obtain access token"""
        query = {
            "query": "mutation Login($apiKey:String!){loginAPI(apiKey:$apiKey){accessToken}}",
            "variables": {"apiKey": self.api_key}
        }

        response = self._execute_query(query, authenticated=False)

        if not response or "data" not in response or "loginAPI" not in response["data"]:
            raise ValueError("Failed to authenticate: Invalid API response")

        self.access_token = response["data"]["loginAPI"]["accessToken"]

        if not self.access_token or self.access_token == "null":
            raise ValueError("Failed to obtain access token")

    def _execute_query(self, query, authenticated=True):
        """Execute a GraphQL query"""
        headers = self.headers.copy()

        if authenticated:
            if not self.access_token:
                raise ValueError("Not authenticated. Call authenticate() first.")
            headers["Authorization"] = f"Bearer {self.access_token}"

        try:
            response = requests.post(
                self.base_url,
                headers=headers,
                json=query,
                timeout=30
            )
            response.raise_for_status()
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Network request failed: {e}")

        try:
            data = response.json()
        except json.JSONDecodeError:
            raise RuntimeError("Failed to parse API response as JSON")

        # Check for GraphQL errors
        if "errors" in data and data["errors"]:
            error_messages = [error.get("message", "Unknown error") for error in data["errors"]]
            raise RuntimeError(f"GraphQL query failed: {', '.join(error_messages)}")

        return data

    def get_report_info(self, report_id):
        """Get report information including status and download URL"""
        query = {
            "query": f"""query queryReport{{
                node(id:"{report_id}"){{
                    id
                    ... on FlexReport{{
                        name
                        result{{
                            status
                            reportUpdatedOn
                            contents{{
                                preSignedUrl
                            }}
                        }}
                    }}
                }}
            }}""",
            "variables": {}
        }

        response = self._execute_query(query)

        if not response or "data" not in response or "node" not in response["data"]:
            raise ValueError("Invalid report information response")

        return response["data"]["node"]

    def execute_report(self, report_id):
        """Trigger report execution"""
        query = {
            "query": f'mutation executeFlexReport{{triggerFlexReportExecution(id:"{report_id}")}}',
            "variables": {}
        }

        self._execute_query(query)

    def download_report(self, url, filename):
        """Download report from pre-signed URL"""
        try:
            response = requests.get(url, timeout=60)
            response.raise_for_status()
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Download failed: {e}")

        with open(filename, 'wb') as f:
            f.write(response.content)

        return Path(filename).stat().st_size


def sanitize_filename(filename):
    """Sanitize filename by removing/replacing problematic characters"""
    # Replace spaces with underscores
    filename = filename.replace(" ", "_")
    # Remove or replace other problematic characters
    filename = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)
    return filename


def format_size(size_bytes):
    """Format file size in human-readable format"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} TB"


def print_header(text):
    """Print formatted section header"""
    print("=" * 46)
    print(text)
    print("=" * 46)


def main():
    """Main execution function"""
    parser = argparse.ArgumentParser(
        description="Executes a CloudHealth FlexReport and downloads the result as a CSV file.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
REQUIREMENTS:
    - Python 3.6+
    - requests module (pip install requests)

USAGE:
    1. Run the script
    2. Enter your CloudHealth API key when prompted
    3. Enter the FlexReport ID when prompted
    4. Script will execute the report, poll for completion, and download the CSV
        """
    )

    parser.parse_args()

    print_header("CloudHealth FlexReport Execution Tool")
    print()

    # Prompt for API key
    try:
        api_key = input("Enter your CloudHealth API key: ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\n\nOperation cancelled by user")
        sys.exit(1)

    if not api_key:
        print("ERROR: API key cannot be empty")
        sys.exit(1)

    print()
    print("Authenticating with CloudHealth API...")

    # Initialize CloudHealth client
    try:
        client = CloudHealthFlexReport(api_key)
        client.authenticate()
    except (ValueError, RuntimeError) as e:
        print(f"ERROR: Authentication failed - {e}")
        sys.exit(1)

    print("Authentication successful")
    print()

    # Prompt for Report ID
    try:
        report_id = input("Enter FlexReport ID: ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\n\nOperation cancelled by user")
        sys.exit(1)

    if not report_id:
        print("ERROR: FlexReport ID cannot be empty")
        sys.exit(1)

    print()

    # Get initial report information
    try:
        report_info = client.get_report_info(report_id)
        report_name = report_info.get("name")

        if not report_name:
            raise ValueError("Failed to retrieve report name")

    except (ValueError, RuntimeError) as e:
        print(f"ERROR: Failed to get report information - {e}")
        sys.exit(1)

    print_header(f"EXECUTING REPORT: {report_name}")
    print()

    # Execute the report
    try:
        client.execute_report(report_id)
    except RuntimeError as e:
        print(f"ERROR: Failed to execute report - {e}")
        sys.exit(1)

    print("Report execution triggered successfully")
    print("Waiting 15 seconds before first status check...")
    print()

    time.sleep(15)

    # Poll for completion
    counter = 1
    sleep_time = 10
    max_retries = 5

    while True:
        try:
            report_info = client.get_report_info(report_id)
            status = report_info.get("result", {}).get("status")

            if not status:
                raise ValueError("Failed to retrieve report status")

        except (ValueError, RuntimeError) as e:
            print(f"ERROR: Failed to check report status - {e}")
            sys.exit(1)

        print(f"Status check #{counter}: {status}")

        # Check if report is completed
        if status == "COMPLETED":
            print()
            print_header("REPORT COMPLETED SUCCESSFULLY")
            break

        # Check if report is queued
        if status == "QUEUED":
            print()
            print("WARNING: Report is QUEUED")
            print("This may indicate the report is waiting for resources.")
            print("Please check status in the CloudHealth platform.")
            sys.exit(1)

        # Check if report failed
        if status == "FAILED":
            print()
            print_header("ERROR: REPORT EXECUTION FAILED")
            print("Please check the report configuration in the CloudHealth platform.")
            sys.exit(1)

        # Check retry limit
        if counter >= max_retries:
            print()
            print_header("TIMEOUT: Report still running after 5 checks")
            print("The report is taking longer than expected.")
            print("Please check status in the CloudHealth platform.")
            sys.exit(1)

        # Increment counter
        counter += 1

        # Exponential backoff: increase sleep time by 1.5x
        if counter > 1:
            sleep_time = int(sleep_time * 1.5)

        print(f"Next status check in {sleep_time} seconds...")
        print()
        time.sleep(sleep_time)

    # Download the report
    print()
    print("Preparing to download report...")

    try:
        download_url = report_info.get("result", {}).get("contents", [{}])[0].get("preSignedUrl")

        if not download_url or download_url == "null":
            raise ValueError("Failed to retrieve download URL")

    except (ValueError, IndexError) as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    # Sanitize the filename
    download_name = sanitize_filename(report_name)
    output_file = f"{download_name}.csv"

    print(f"Report Name: {report_name}")
    print(f"Download URL: {download_url}")
    print(f"Saving as: {output_file}")
    print()

    # Download the report
    try:
        file_size = client.download_report(download_url, output_file)
    except RuntimeError as e:
        print()
        print_header("ERROR: DOWNLOAD FAILED")
        print("Please try downloading manually from the CloudHealth platform.")
        sys.exit(1)

    print_header("DOWNLOAD COMPLETE")
    print(f"File saved: {output_file}")
    print()
    print(f"File size: {format_size(file_size)}")
    print()


if __name__ == "__main__":
    main()
