#!/usr/bin/env bash

# Converts a CSV file to Parquet format.
# https://www.databricks.com/glossary/what-is-parquet

set -e

if [[ -z "$1" ]]; then
  read -r -p "CSV to copy to Parquet: " filenameext
else
  filenameext=$1
fi

# Check if the input CSV file exists
if [[ ! -f "$filenameext" ]]; then
  echo "Error: Input CSV file not found."
  exit 1
fi

filename=$(basename "$filenameext" .csv)
output_parquet="$filename.parquet"

# Check if DuckDB is installed and available in the PATH
if ! command -v duckdb &> /dev/null; then
  echo "Error: DuckDB command not found. Make sure DuckDB is installed and available in the PATH."
  exit 1
fi

# Perform the conversion from CSV to Parquet
duckdb -s "copy '$filenameext' to '$output_parquet' (FORMAT PARQUET);" || {
  echo "Error: Conversion from CSV to Parquet failed."
  exit 1
}

echo ""
echo "Conversion successful. Output Parquet file: $output_parquet"
echo ""

# Display the information about the generated Parquet file
ls -lh "$output_parquet"
