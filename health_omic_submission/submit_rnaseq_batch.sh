#!/bin/sh

usage() {
	echo "Usage: $0 -r <repo_dir> -i <inputs_dir> -c <charge_code> -o <output_uri_base> -a <aws_shared_credentials_file> [-s <run_ids_status_tsv>]" >&2
}

repo_dir=""
inputs_dir=""
charge_code=""
output_uri_base=""
aws_shared_credentials_file=""
run_ids_status_file=""

while getopts "r:i:c:o:a:s:" opt; do
	case "$opt" in
		r) repo_dir=$OPTARG ;;
		i) inputs_dir=$OPTARG ;;
		c) charge_code=$OPTARG ;;
		o) output_uri_base=$OPTARG ;;
		a) aws_shared_credentials_file=$OPTARG ;;
		s) run_ids_status_file=$OPTARG ;;
		*) usage; exit 1 ;;
	esac
done

if [ -z "$repo_dir" ] || [ -z "$inputs_dir" ] || [ -z "$charge_code" ] || [ -z "$output_uri_base" ] || [ -z "$aws_shared_credentials_file" ]; then
	usage
	exit 1
fi

workflow_id=2983919

timestamp=$(date +"%Y%m%d-%H%M%S")
run_id_output="$repo_dir/run_ids_${timestamp}.tsv"
printf "sample_id\trun_id\n" > "$run_id_output"

resubmit_sample_ids_file=""
resubmit_status_output=""
if [ -n "$run_ids_status_file" ]; then
	if [ ! -f "$run_ids_status_file" ]; then
		echo "run_ids_status file not found: $run_ids_status_file" >&2
		exit 1
	fi
	resubmit_sample_ids_file=$(mktemp)
	awk -F'\t' 'NR>1 && ($3=="FAILED" || $3=="CANCELLED"){print $1}' "$run_ids_status_file" > "$resubmit_sample_ids_file"
	resubmit_status_output="$repo_dir/run_ids_status_resubmit_${timestamp}.tsv"
	printf "sample_id\trun_id\tstatus\n" > "$resubmit_status_output"
fi

for parameters in "$inputs_dir"/*_inputs.json; do
	[ -f "$parameters" ] || continue
	name=$(basename "$parameters" _inputs.json)
	if [ -n "$resubmit_sample_ids_file" ] && ! grep -Fxq "$name" "$resubmit_sample_ids_file"; then
		continue
	fi
	output_uri="$output_uri_base$name/"
	echo "Starting run for $name with parameters from $parameters"
	docker run -ti \
	-v "$repo_dir:$repo_dir" \
	-v "$HOME/.aws:$HOME/.aws" \
	-e task=start_run \
	-e charge_code="$charge_code" \
	-e aws_profile=default \
	-e AWS_SHARED_CREDENTIALS_FILE="$aws_shared_credentials_file" \
	-e workflow_id=$workflow_id \
	-e parameters="$parameters" \
	-e name="$name" \
	-e output_uri="$output_uri" \
	-e run_metadata_output_dir="$repo_dir" \
	--rm rtibiocloud/healthomics_tools:v2.0_5e6c048
done

for parameters in "$inputs_dir"/*.json; do
	[ -f "$parameters" ] || continue
	name=$(basename "$parameters" _inputs.json)
	if [ -n "$resubmit_sample_ids_file" ] && ! grep -Fxq "$name" "$resubmit_sample_ids_file"; then
		continue
	fi
	metadata_file="$repo_dir/${name}_metadata.json"
	if [ ! -f "$metadata_file" ]; then
		echo "Metadata file not found for $name: $metadata_file" >&2
		continue
	fi
	run_id=$(python3 - <<'PY' "$metadata_file"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

run_id = data.get("id")

if not run_id:
    raise SystemExit(f"id not found in {path}")

print(run_id)
PY
	)
	sample_id="$name"
	echo "Run ID for $sample_id: $run_id"
	printf "%s\t%s\n" "$sample_id" "$run_id" >> "$run_id_output"
	if [ -n "$resubmit_status_output" ]; then
		printf "%s\t%s\tRESUBMITTED\n" "$sample_id" "$run_id" >> "$resubmit_status_output"
	fi
done

if [ -n "$resubmit_sample_ids_file" ]; then
	rm -f "$resubmit_sample_ids_file"
	echo "Wrote resubmit status to: $resubmit_status_output"
fi
