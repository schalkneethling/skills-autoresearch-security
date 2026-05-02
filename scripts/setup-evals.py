#!/usr/bin/env python3
"""
Materialise eval case input files from eval-cases.json.

For each eval case, creates:
  workspace/{phase}/eval-{id}/input/{filename}  — the input files
  workspace/{phase}/eval-{id}/task.md            — the task prompt

Usage:
  python3 scripts/setup-evals.py workspace/baseline
  python3 scripts/setup-evals.py workspace/iteration-1
"""

import json
import os
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/setup-evals.py <output-dir>")
        sys.exit(1)

    output_dir = sys.argv[1]
    evals_file = "evals/eval-cases.json"

    if not os.path.exists(evals_file):
        print(f"Error: {evals_file} not found")
        sys.exit(1)

    with open(evals_file) as f:
        data = json.load(f)

    for eval_case in data["evals"]:
        eval_id = eval_case["id"]
        eval_dir = os.path.join(output_dir, f"eval-{eval_id}")
        input_dir = os.path.join(eval_dir, "input")
        output_subdir = os.path.join(eval_dir, "output")

        os.makedirs(input_dir, exist_ok=True)
        os.makedirs(output_subdir, exist_ok=True)

        # Write input files
        for filename, content in eval_case["input_files"].items():
            filepath = os.path.join(input_dir, filename)
            with open(filepath, "w") as f:
                f.write(content)
            print(f"  Created {filepath}")

        # Write task.md
        task_path = os.path.join(eval_dir, "task.md")
        with open(task_path, "w") as f:
            f.write(eval_case["task"])
        print(f"  Created {task_path}")

    print(f"\nSetup complete: {len(data['evals'])} eval cases in {output_dir}/")


if __name__ == "__main__":
    main()
