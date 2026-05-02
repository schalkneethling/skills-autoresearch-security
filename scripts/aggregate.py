#!/usr/bin/env python3
"""Aggregate scoring results from an autoresearch iteration or baseline run.

Usage:
    python3 scripts/aggregate.py workspace/baseline/
    python3 scripts/aggregate.py workspace/iteration-1/
    python3 scripts/aggregate.py workspace/iteration-1/ --baseline workspace/baseline/

When --baseline is provided, the summary includes a delta comparison.
"""

import json
import os
import sys
from pathlib import Path


def load_scores(directory: Path) -> list[dict]:
    """Load all scores-*.json files from a directory."""
    scores = []
    for f in sorted(directory.glob("scores-*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
                scores.append(data)
        except (json.JSONDecodeError, FileNotFoundError) as e:
            print(f"  Warning: Could not load {f}: {e}", file=sys.stderr)
    return scores


def aggregate(scores: list[dict]) -> dict:
    """Compute per-dimension and overall averages from score files."""
    dim_totals: dict[str, list[float]] = {}
    eval_composites: list[dict] = []
    all_met: list[str] = []
    all_missed: list[str] = []

    for entry in scores:
        eval_id = entry.get("eval_id", "?")
        eval_name = entry.get("eval_name", "unknown")
        eval_type = entry.get("eval_type", "unknown")
        score_map = entry.get("scores", {})

        eval_scores = []
        for dim_key, dim_data in score_map.items():
            if isinstance(dim_data, dict) and dim_data.get("score") is not None:
                score_val = float(dim_data["score"])
                dim_totals.setdefault(dim_key, []).append(score_val)
                eval_scores.append(score_val)

        composite = sum(eval_scores) / len(eval_scores) if eval_scores else 0.0

        eval_composites.append({
            "eval_id": eval_id,
            "eval_name": eval_name,
            "eval_type": eval_type,
            "composite": round(composite, 2),
            "dimension_scores": {
                k: v["score"] for k, v in score_map.items()
                if isinstance(v, dict) and v.get("score") is not None
            },
        })

        all_met.extend(entry.get("expectations_met", []))
        all_missed.extend(entry.get("expectations_missed", []))

    # Per-dimension averages
    dim_averages = {}
    for dim, vals in sorted(dim_totals.items()):
        dim_averages[dim] = {
            "mean": round(sum(vals) / len(vals), 2),
            "min": min(vals),
            "max": max(vals),
            "count": len(vals),
        }

    overall = sum(d["mean"] for d in dim_averages.values()) / len(dim_averages) if dim_averages else 0.0

    # Per-type breakdown
    type_breakdown = {}
    for ec in eval_composites:
        t = ec["eval_type"]
        type_breakdown.setdefault(t, []).append(ec["composite"])
    type_averages = {
        t: round(sum(vals) / len(vals), 2)
        for t, vals in type_breakdown.items()
    }

    return {
        "overall_composite": round(overall, 2),
        "type_averages": type_averages,
        "dimension_averages": dim_averages,
        "eval_results": eval_composites,
        "total_expectations_met": len(all_met),
        "total_expectations_missed": len(all_missed),
        "frequently_missed": _frequency_count(all_missed),
    }


def _frequency_count(items: list[str], top_n: int = 10) -> list[dict]:
    """Count frequency of items, return top N."""
    counts: dict[str, int] = {}
    for item in items:
        counts[item] = counts.get(item, 0) + 1
    sorted_items = sorted(counts.items(), key=lambda x: x[1], reverse=True)
    return [{"expectation": k, "count": v} for k, v in sorted_items[:top_n]]


def compute_delta(current: dict, baseline: dict) -> dict:
    """Compute the difference between current and baseline scores."""
    delta = {
        "overall_delta": round(
            current["overall_composite"] - baseline["overall_composite"], 2
        ),
        "dimension_deltas": {},
        "eval_deltas": [],
        "type_deltas": {},
    }

    # Per-dimension delta
    all_dims = set(current.get("dimension_averages", {}).keys()) | set(
        baseline.get("dimension_averages", {}).keys()
    )
    for dim in sorted(all_dims):
        curr_val = current.get("dimension_averages", {}).get(dim, {}).get("mean", 0)
        base_val = baseline.get("dimension_averages", {}).get(dim, {}).get("mean", 0)
        d = round(curr_val - base_val, 2)
        delta["dimension_deltas"][dim] = {
            "baseline": base_val,
            "current": curr_val,
            "delta": d,
            "status": "improved" if d > 0.1 else ("regressed" if d < -0.1 else "unchanged"),
        }

    # Per-eval delta (matched by eval_id)
    baseline_by_id = {e["eval_id"]: e for e in baseline.get("eval_results", [])}
    for ec in current.get("eval_results", []):
        base_ec = baseline_by_id.get(ec["eval_id"])
        if base_ec:
            d = round(ec["composite"] - base_ec["composite"], 2)
            delta["eval_deltas"].append({
                "eval_id": ec["eval_id"],
                "eval_name": ec["eval_name"],
                "baseline": base_ec["composite"],
                "current": ec["composite"],
                "delta": d,
                "status": "improved" if d > 0.1 else ("regressed" if d < -0.1 else "unchanged"),
            })

    # Per-type delta
    for t in set(list(current.get("type_averages", {}).keys()) + list(baseline.get("type_averages", {}).keys())):
        curr_val = current.get("type_averages", {}).get(t, 0)
        base_val = baseline.get("type_averages", {}).get(t, 0)
        d = round(curr_val - base_val, 2)
        delta["type_deltas"][t] = {
            "baseline": base_val,
            "current": curr_val,
            "delta": d,
        }

    return delta


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/aggregate.py <directory> [--baseline <baseline_dir>]")
        sys.exit(1)

    target_dir = Path(sys.argv[1])
    baseline_dir = None

    if "--baseline" in sys.argv:
        idx = sys.argv.index("--baseline")
        if idx + 1 < len(sys.argv):
            baseline_dir = Path(sys.argv[idx + 1])

    if not target_dir.exists():
        print(f"Error: {target_dir} does not exist")
        sys.exit(1)

    scores = load_scores(target_dir)
    if not scores:
        print(f"Error: No score files found in {target_dir}")
        sys.exit(1)

    summary = aggregate(scores)

    # Include delta if baseline provided
    if baseline_dir and baseline_dir.exists():
        baseline_summary_path = baseline_dir / "summary.json"
        if baseline_summary_path.exists():
            with open(baseline_summary_path) as fh:
                baseline_summary = json.load(fh)
            summary["baseline_comparison"] = compute_delta(summary, baseline_summary)

    output_path = target_dir / "summary.json"
    with open(output_path, "w") as fh:
        json.dump(summary, fh, indent=2)

    # Print summary to stdout
    print(f"\n{'=' * 50}")
    print(f"  Score Summary: {target_dir.name}")
    print(f"{'=' * 50}")
    print(f"  Overall composite: {summary['overall_composite']} / 3.00")
    print()

    if summary.get("type_averages"):
        print("  By eval type:")
        for t, avg in summary["type_averages"].items():
            print(f"    {t}: {avg}")
        print()

    print("  By dimension:")
    for dim, data in summary["dimension_averages"].items():
        bar = "█" * int(data["mean"] * 10) + "░" * (30 - int(data["mean"] * 10))
        print(f"    {dim:<24} {data['mean']:.2f}  {bar}")
    print()

    print(f"  Expectations met:    {summary['total_expectations_met']}")
    print(f"  Expectations missed: {summary['total_expectations_missed']}")

    if summary.get("baseline_comparison"):
        delta = summary["baseline_comparison"]
        print(f"\n  Baseline delta: {delta['overall_delta']:+.2f}")
        for dim, d in delta["dimension_deltas"].items():
            arrow = "↑" if d["delta"] > 0 else ("↓" if d["delta"] < 0 else "→")
            print(f"    {dim:<24} {d['baseline']:.2f} → {d['current']:.2f} ({d['delta']:+.2f}) {arrow}")

    if summary.get("frequently_missed"):
        print("\n  Most frequently missed expectations:")
        for item in summary["frequently_missed"][:5]:
            print(f"    [{item['count']}x] {item['expectation'][:80]}")

    print(f"\n  Written to {output_path}")
    print()


if __name__ == "__main__":
    main()
