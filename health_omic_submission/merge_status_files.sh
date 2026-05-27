#!/bin/bash

# Script to merge run status files and update failed runs with successful reruns
# Usage: ./merge_status_files.sh <original_status_file> <rerun_file1> [rerun_file2] ...

if [ $# -lt 2 ]; then
    echo "Usage: $0 <original_status_file> <rerun_file1> [rerun_file2] ..."
    exit 1
fi

original_file="$1"
shift
rerun_files=("$@")

# Build output filename from original input with "_final" appended
if [[ "$original_file" == *.* ]]; then
    output_file="${original_file%.*}_final.${original_file##*.}"
else
    output_file="${original_file}_final"
fi

# Create temporary file for the result
temp_file=$(mktemp)
cp "$original_file" "$temp_file"

# Process each rerun file
for rerun_file in "${rerun_files[@]}"; do
    if [ ! -f "$rerun_file" ]; then
        echo "Warning: File not found: $rerun_file"
        continue
    fi
    
    # Read rerun file and update original
    while IFS=$'\t' read -r sample_id run_id status; do
        # Skip header line
        if [ "$sample_id" = "sample_id" ]; then
            continue
        fi

        # Only apply updates from successful reruns
        if [ "$status" != "COMPLETED" ]; then
            continue
        fi
        
        # Update the temp file: replace failed entry with successful rerun
        awk -F$'\t' -v sid="$sample_id" -v rid="$run_id" -v st="$status" \
            'NR==1 {print; next} $1==sid {$2=rid; $3=st} {print}' \
            OFS=$'\t' "$temp_file" > "${temp_file}.tmp"
        mv "${temp_file}.tmp" "$temp_file"
    done < "$rerun_file"
done

# Output the merged file to disk
mv "$temp_file" "$output_file"
echo "Merged file written to: $output_file"

# Cleanup
if [ -f "$temp_file" ]; then
    rm "$temp_file"
fi