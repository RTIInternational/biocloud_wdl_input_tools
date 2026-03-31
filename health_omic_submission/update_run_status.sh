#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: $0 <run_ids_tsv> [output_tsv]" >&2
}

if [ $# -lt 1 ]; then
	usage
	exit 1
fi

run_ids_file=$1

HOME_DIR="$HOME"
echo "$HOME_DIR"
if [ ! -f "$run_ids_file" ]; then
	echo "run_ids file not found: $run_ids_file" >&2
	exit 1
fi

if [ $# -ge 2 ]; then
	output_tsv=$2
else
	base_dir=$(dirname "$run_ids_file")
	timestamp=$(date +"%Y%m%d-%H%M%S")
	output_tsv="$base_dir/run_status_${timestamp}.tsv"
fi

printf "sample_id\trun_id\tstatus\n" > "$output_tsv"

while IFS=$'\t' read -r sample_id run_id; do
	[ -n "$sample_id" ] || continue
	if [ "$sample_id" = "sample_id" ]; then
		continue
	fi
	if [ -z "$run_id" ]; then
		echo "Missing run_id for sample_id: $sample_id" >&2
		continue
	fi
    echo $run_id
	status=$(docker run --rm -v "$HOME_DIR/.aws:/root/.aws:ro" amazon/aws-cli:2.34.10 omics get-run --id "$run_id" --query status --output text 2>/dev/null || true)
    echo $status
	if [ -z "$status" ] || [ "$status" = "None" ]; then
		status="UNKNOWN"
	fi

	printf "%s\t%s\t%s\n" "$sample_id" "$run_id" "$status" >> "$output_tsv"
done < "$run_ids_file"

echo "Wrote run status to: $output_tsv"