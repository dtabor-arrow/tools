# Execute and Download Scripts

These scripts execute a CloudHealth FlexReport and download the resulting CSV file.

## Available Versions

### Bash Script 
**File:** `execute-and-download-flexreport.sh`

Use this version if you prefer bash or need to run in environments without Python.

**Requirements:**
- bash (4.0+)
- curl
- jq

### Python Script
**File:** `execute-and-download-flexreport.py`

Use this version if you prefer Python or need more extensibility.

**Requirements:**
- Python 3.6+
- requests module: `pip install requests`

## How It Works

1. Prompts for your CloudHealth API key
2. Prompts for the FlexReport ID
3. Authenticates with CloudHealth API
4. Triggers report execution
5. Polls for completion with exponential backoff (up to 5 checks)
6. Downloads the report as a CSV file to the current directory

## Getting Your FlexReport ID

1. Log in to CloudHealth platform
2. Navigate to Reports > FlexReports
3. Open the report you want to execute
4. Copy the report ID from the URL

Example FlexReport URL: `https://apps.cloudhealthtech.com/ui/reports/flexreports/view/crn:63253:flexreports/6d24474b-d599-4a12-8a6d-5cca086898qq?...`

Example FlexReport ID: `crn:63253:flexreports/6d24474b-d599-4a12-8a6d-5cca086898qq`

## Output Files

Files are saved to the current directory with the report name as the filename (spaces replaced with underscores, special characters removed).

Example: "Monthly Cost Report" becomes `Monthly_Cost_Report.csv`

## Help

For help using any script, run with `-h` or `--help` flag:
