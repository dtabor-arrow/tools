import json
import requests
import sys
import random
import string

# Function to prompt the user for the filename if not provided as a parameter
def get_filename():
    if len(sys.argv) > 1:
        return sys.argv[1]
    else:
        return input("Enter the JSON filename: ")

# Get the report definition filename
json_filename = get_filename()

# Read the FlexReport variables from the report definition file
try:
    with open(json_filename, "r") as json_file:
        report_definitions = json.load(json_file)
except FileNotFoundError:
    print("File not found:", json_filename)
    sys.exit(1)
except Exception as e:
    print("Error reading JSON file:", str(e))
    sys.exit(1)

# Prompt the user for the customer tenant API key
api_key = input("Enter your CloudHealth API key: ")

# Define the GraphQL query
graphql_query = {
    "query": "mutation Login($apiKey: String!) { loginAPI(apiKey: $apiKey) { accessToken } }",
    "variables": {
        "apiKey": api_key
    }
}

# GraphQL endpoint URL
graphql_endpoint = 'https://apps.cloudhealthtech.com/graphql'

# GraphQL query to create the FlexReport
flex_report_query = """
mutation CreateFlexReport($name: String!, $description: String!, $sqlStatement: String!, $needBackLinkingForTags: Boolean!, $dataGranularity: FlexReportDataGranularity!, $limit: Int!, $timeRangeLast: Int!, $excludeCurrent: Boolean!), 
{
  createFlexReport(input: {
    name: $name,
    description: $description,
    notification: {sendUserEmail: false},
    query: {
      sqlStatement: $sqlStatement,
      needBackLinkingForTags: $needBackLinkingForTags,
      dataGranularity: $dataGranularity,
      limit: $limit,
      timeRange: {last: $timeRangeLast excludeCurrent: $excludeCurrent}
    }
  }) {
    id
    name
  }
}
"""

# GraphQL query to obtain an access token
get_access_token_query = """
mutation GetAccessToken($apiKey: String!) {
  loginAPI(apiKey: $apiKey) {
    accessToken
  }
}
"""

# Set the headers for the GraphQL requests
headers = {
    "Content-Type": "application/json"
}

# Make the GraphQL API call to get the access token
try:
    access_token_response = requests.post(
        graphql_endpoint,
        json={"query": get_access_token_query, "variables": {"apiKey": api_key}},
        headers=headers
    )
    access_token_response.raise_for_status()
    access_token = access_token_response.json()["data"]["loginAPI"]["accessToken"]
except requests.exceptions.RequestException as e:
    print("Failed to retrieve access token:", e)
    sys.exit(1)
except KeyError as e:
    print("Error parsing access token response:", e)
    sys.exit(1)

# List to store generated FlexReport IDs
flex_report_ids = []

# List to store names of successfully created reports
successful_reports = []

# Iterate through each report definition and create FlexReports
for report_definition in report_definitions:
    report_name = report_definition["name"]
    random_suffix = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
    report_name_with_suffix = f"{report_name} {random_suffix}"  # Append random string to the report name

    flex_report_variables = {
        "name": report_name_with_suffix,
        "description": report_definition["description"],
        "sqlStatement": report_definition["sqlStatement"],
        "dataGranularity": report_definition["dataGranularity"],
        "limit": int(report_definition["limit"]),  # Convert limit to integer
        "timeRangeLast": int(report_definition["timeRange"]),  # Convert timeRangeLast to integer
        "needBackLinkingForTags": bool(report_definition["backlinking"]),
        "excludeCurrent": bool(report_definition["excludeCurrent"])
    }

    # Make the GraphQL API call to create the FlexReport
    flex_report_response = requests.post(
        graphql_endpoint,
        json={"query": flex_report_query, "variables": flex_report_variables},
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + access_token}
    )

    if flex_report_response.status_code == 200:
        flex_report_result = flex_report_response.json()
        if flex_report_result is not None:
            flex_report_data = flex_report_result.get("data", {})
            if flex_report_data:
                create_flex_report_data = flex_report_data.get("createFlexReport", {})
                if create_flex_report_data:
                    flex_report_id = create_flex_report_data.get("id")
                    if flex_report_id:
                        flex_report_ids.append(flex_report_id)  # Store FlexReport ID
                        print(f"FlexReport '{report_name_with_suffix}' created successfully!")
                        print("FlexReport ID:", flex_report_id)
                        print()
                        successful_reports.append(report_name_with_suffix)  # Store successfully created reports
                    else:
                        print(f"Failed to create FlexReport '{report_name_with_suffix}'. FlexReport ID not found in response.")
                else:
                    print(f"Failed to create FlexReport '{report_name_with_suffix}'. 'createFlexReport' key not found in response.")
            else:
                print(f"Failed to create FlexReport '{report_name_with_suffix}'. 'data' key not found in response.")
        else:
            print(f"Failed to create FlexReport '{report_name_with_suffix}'. Empty response received.")
    else:
        print(f"Failed to create FlexReport '{report_name_with_suffix}'. Status code:", flex_report_response.status_code)
        print("Response:", flex_report_response.text)

# Save generated FlexReport IDs to a file. For use with cleanup.py
with open("previous-run.list", "w") as id_file:
    for flex_id in flex_report_ids:
        id_file.write(f"{flex_id}\n")

# Save list of successfully created reports in case of errors
if successful_reports:
    with open("successful_reports.list", "w") as success_file:
        for report_name in successful_reports:
            success_file.write(f"{report_name}\n")
