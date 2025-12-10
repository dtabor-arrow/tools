#!/usr/bin/env python3

"""
CSV to Parquet Converter
Converts CSV files to Parquet format using DuckDB
"""

import sys
import argparse
from pathlib import Path

# Check for required dependencies
try:
    import duckdb
except ImportError:
    print("ERROR: Missing required Python module 'duckdb'")
    print("Install with: pip install duckdb")
    sys.exit(1)


def format_size(size_bytes):
    """Format file size in human-readable format"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f}{unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f}TB"


def convert_csv_to_parquet(csv_file):
    """Convert CSV file to Parquet format using DuckDB"""

    # Validate input file exists
    csv_path = Path(csv_file)
    if not csv_path.exists():
        print(f"ERROR: Input CSV file not found: {csv_file}")
        sys.exit(1)

    if not csv_path.is_file():
        print(f"ERROR: {csv_file} is not a file")
        sys.exit(1)

    # Generate output filename
    output_parquet = csv_path.stem + ".parquet"
    output_path = csv_path.parent / output_parquet

    print(f"Converting {csv_path.name} to Parquet format...")
    print()

    try:
        # Use DuckDB to convert CSV to Parquet
        conn = duckdb.connect(':memory:')
        conn.execute(f"COPY '{csv_file}' TO '{output_path}' (FORMAT PARQUET);")
        conn.close()

    except Exception as e:
        print(f"ERROR: Conversion from CSV to Parquet failed")
        print(f"Details: {e}")
        sys.exit(1)

    print("Conversion successful!")
    print(f"Output Parquet file: {output_parquet}")
    print()

    # Display file information
    if output_path.exists():
        file_size = output_path.stat().st_size
        print(f"File: {output_path}")
        print(f"Size: {format_size(file_size)}")
    else:
        print("WARNING: Output file was not created")
        sys.exit(1)


def main():
    """Main execution function"""
    parser = argparse.ArgumentParser(
        description="Convert CSV files to Parquet format using DuckDB.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
REQUIREMENTS:
    - Python 3.6+
    - duckdb module (pip install duckdb)

USAGE EXAMPLES:
    # Convert a specific CSV file
    ./to-parquet.py report.csv

    # Run interactively (prompts for filename)
    ./to-parquet.py

OUTPUT:
    Creates a .parquet file in the same directory as the input CSV file.
        """
    )

    parser.add_argument(
        'csv_file',
        nargs='?',
        help='CSV file to convert to Parquet format'
    )

    args = parser.parse_args()

    # Get CSV filename from argument or prompt
    if args.csv_file:
        csv_file = args.csv_file
    else:
        try:
            csv_file = input("CSV file to convert to Parquet: ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\n\nOperation cancelled by user")
            sys.exit(1)

        if not csv_file:
            print("ERROR: Filename cannot be empty")
            sys.exit(1)

    # Convert the file
    convert_csv_to_parquet(csv_file)


if __name__ == "__main__":
    main()
