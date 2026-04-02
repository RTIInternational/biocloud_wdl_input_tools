#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <rna_seq_run_s3> <run_id_status_tsv> <analysis_name> <annotation_gtf>" >&2
    exit 1
fi

rna_seq_run_s3=${1%/}
run_id_status_tsv=$2

analysis_name=$3
annotation_gtf=$4

if [[ ! -f "$run_id_status_tsv" ]]; then
    echo "run_id_status_tsv not found: $run_id_status_tsv" >&2
    exit 1
fi

run_id_status_dir=$(dirname "$run_id_status_tsv")
timestamp=$(date +"%Y%m%d-%H%M%S")
output_json="$run_id_status_dir/${analysis_name}_${timestamp}.inputs.json"

bucket=$(echo "$rna_seq_run_s3" | sed -E 's#^s3://([^/]+)/?.*#\1#')

mapfile -t sample_run_pairs < <(
    python3 - <<'PY' "$run_id_status_tsv"
import csv
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("r", encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    fieldnames = reader.fieldnames or []
    required = {"sample_id", "run_id"}
    missing = sorted(required - set(fieldnames))
    if missing:
        raise SystemExit(
            f"Missing required column(s) in {path}: {', '.join(missing)}"
        )

    for row in reader:
        sample_id = (row.get("sample_id") or "").strip()
        run_id = (row.get("run_id") or "").strip()
        if sample_id and run_id:
            print(f"{sample_id}\t{run_id}")
PY
)

if [[ ${#sample_run_pairs[@]} -eq 0 ]]; then
    echo "No sample_id/run_id pairs found in $run_id_status_tsv" >&2
    exit 1
fi

sample_names=()
multiqc_input_dirs=()
salmon_quant_sf_files=()
multiqc_reports=()

for sample_run_pair in "${sample_run_pairs[@]}"; do
    IFS=$'\t' read -r sample_id run_id <<< "$sample_run_pair"
    echo "Processing sample: $sample_id (run_id: $run_id)"

    prefix="$rna_seq_run_s3/$sample_id/$run_id/"
    echo $prefix
    mapfile -t keys < <(aws s3 ls "$prefix" --recursive | awk '{print $4}')

    multiqc_input_key=$(printf '%s\n' "${keys[@]}" | grep -E '/out/multiqc_input_dir/.*\.tar\.gz$' | head -n 1 || true)
    salmon_quant_key=$(printf '%s\n' "${keys[@]}" | grep -E '/out/salmon_quant_sf/quant\.sf$' | head -n 1 || true)
    multiqc_report_key=$(printf '%s\n' "${keys[@]}" | grep -E '/out/multiqc_report/.*\.html$' | head -n 1 || true)

    sample_names+=("$sample_id")
    if [[ -n "$multiqc_input_key" ]]; then
        multiqc_input_dirs+=("s3://$bucket/$multiqc_input_key")
    else
        multiqc_input_dirs+=("")
    fi

    if [[ -n "$salmon_quant_key" ]]; then
        salmon_quant_sf_files+=("s3://$bucket/$salmon_quant_key")
    else
        salmon_quant_sf_files+=("")
    fi

    if [[ -n "$multiqc_report_key" ]]; then
        multiqc_reports+=("s3://$bucket/$multiqc_report_key")
    else
        multiqc_reports+=("")
    fi
done

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

printf '%s\n' "${sample_names[@]}" > "$tmp_dir/sample_names.txt"
printf '%s\n' "${multiqc_input_dirs[@]}" > "$tmp_dir/multiqc_input_dirs.txt"
printf '%s\n' "${salmon_quant_sf_files[@]}" > "$tmp_dir/salmon_quant_sf_files.txt"
printf '%s\n' "${multiqc_reports[@]}" > "$tmp_dir/multiqc_reports.txt"

python3 - <<'PY' "$tmp_dir/sample_names.txt" "$tmp_dir/multiqc_input_dirs.txt" "$tmp_dir/salmon_quant_sf_files.txt" "$tmp_dir/multiqc_reports.txt" "$output_json" "$analysis_name" "$annotation_gtf"
import json
import sys
from pathlib import Path

def read_lines(path: str) -> list[str]:
    return [line.rstrip("\n") for line in Path(path).read_text(encoding="utf-8").splitlines()]

sample_names = read_lines(sys.argv[1])
multiqc_input_dirs = read_lines(sys.argv[2])
salmon_quant_sf_files = read_lines(sys.argv[3])
multiqc_reports = read_lines(sys.argv[4])
output_json = Path(sys.argv[5])
analysis_name = sys.argv[6]
annotation_gtf = sys.argv[7]

data = {
    "merge_rnaseq_samples_wf.analysis_name": analysis_name,
    "merge_rnaseq_samples_wf.annotation_gtf": annotation_gtf,
    "merge_rnaseq_samples_wf.sample_names": sample_names,
    "merge_rnaseq_samples_wf.multiqc_input_dirs": multiqc_input_dirs,
    "merge_rnaseq_samples_wf.salmon_quant_sf_files": salmon_quant_sf_files,
    "merge_rnaseq_samples_wf.multiqc_reports": multiqc_reports,
}

output_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY

echo "Saved output JSON: $output_json"

