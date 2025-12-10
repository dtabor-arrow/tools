# Execute and Download Scripts

These scripts execute a CloudHealth FlexReport and download the resulting CSV file.

## Available Versions

### Bash Script 
**File:** `execute-and-download-flexreport-beta.sh`

Use this version if you prefer bash or need to run in environments without Python.

**Requirements:**
- bash (4.0+)
- curl
- jq

**Usage:**
```bash
./execute-and-download-flexreport-beta.sh
```

### Python Script
**File:** `execute-and-download-flexreport.py`

Use this version if you prefer Python or need more extensibility.

**Requirements:**
- Python 3.6+
- requests module: `pip install requests`

**Usage:**
```bash
./execute-and-download-flexreport.py
```

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

## Error Handling

The scripts will exit with an error message if:
- Authentication fails
- Report ID is invalid
- Report execution fails
- Report is queued for too long
- Download fails

All errors include clear messages about next steps.

## Troubleshooting

**Problem:** "Missing required dependencies"
**Solution:** Install the required tools:
- Bash: `brew install jq` (curl is usually pre-installed)
- Python: `pip install requests`

**Problem:** Report times out after 5 checks
**Solution:** The report is taking longer than expected. Check status in the CloudHealth platform and download manually if needed.

**Problem:** Report status is QUEUED
**Solution:** The platform may be experiencing high load. Try again later or check with CloudHealth support.

**Problem:** Report status is FAILED
**Solution:** Check the report configuration in the CloudHealth platform. The report may have invalid parameters or data issues.

## Help

For help using any script, run with `-h` or `--help` flag:
```bash
./execute-and-download-flexreport-beta.sh --help
./execute-and-download-flexreport.py --help
```

