import json
from pathlib import Path
import argparse

def split_json(input_path: Path, output_dir: Path, array_key: str | None = None) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    with input_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    if array_key:
        items = data.get(array_key, [])
    else:
        if isinstance(data, list):
            items = data
        elif isinstance(data, dict):
            items = list(data.values())
        else:
            raise ValueError("Unsupported JSON structure")

for i, item in enumerate(data, start=1):
    sample_name = None
    if isinstance(item, dict):
        sample_name = item.get("rnaseq_pe_wf.sample_name")
    filename = f"{sample_name}_inputs.json" if sample_name else f"block_{i}.json"
    out_file = f"{output_dir}/{filename}"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(item, f, indent=2, ensure_ascii=False)


def main() -> None:
    parser = argparse.ArgumentParser(description="Split a JSON file into multiple files.")
    parser.add_argument("input", type=Path, help="Path to input JSON file")
    parser.add_argument("output_dir", type=Path, help="Directory to write split files")
    parser.add_argument("--array-key", type=str, default=None, help="Key containing array to split")
    args = parser.parse_args()

    split_json(args.input, args.output_dir, args.array_key)


if __name__ == "__main__":
    main()