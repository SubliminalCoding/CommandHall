#!/usr/bin/env python3
"""Validate evidence-backed product requirements and build-plan coverage."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REQUIREMENT = re.compile(r"(?ms)^### (WSP-(P[012])-\d+) — (.+?)\n(.*?)(?=^### WSP-|^## |\Z)")
FIELDS = ("- **Evidence**:", "- **Rationale**:", "- **Dependencies**:", "- **Acceptance**:")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("corpora/maxbladetv"))
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def validate(root: Path) -> tuple[list[str], dict[str, object]]:
    errors: list[str] = []
    specs = root / "specs"
    required_files = (
        "triangulated_kernel.md",
        "operator_library.md",
        "session_kickoff.md",
        "product_requirements.md",
        "architecture_map.md",
        "implementation_blueprint.md",
    )
    texts: dict[str, str] = {}
    for name in required_files:
        path = specs / name
        try:
            texts[name] = path.read_text(encoding="utf-8")
        except OSError as error:
            errors.append(f"cannot read {path}: {error}")

    requirements_text = texts.get("product_requirements.md", "")
    matches = list(REQUIREMENT.finditer(requirements_text))
    ids: set[str] = set()
    counts = {"P0": 0, "P1": 0, "P2": 0}
    for match in matches:
        requirement_id, priority, title, block = match.groups()
        if requirement_id in ids:
            errors.append(f"duplicate requirement id: {requirement_id}")
        ids.add(requirement_id)
        counts[priority] += 1
        for field in FIELDS:
            if field not in block:
                errors.append(f"{requirement_id} {title!r} is missing {field}")
        if not re.search(r"§\d+", block):
            errors.append(f"{requirement_id} has no quote-bank evidence anchor")
        for sentence in re.findall(r"[^.\n]*\b\d+(?:\.\d+)?\s*(?:ms|seconds?|cycles?|times?|nodes?|KiB|%)\b[^.\n]*", block, re.I):
            if "inference: acceptance target" not in sentence and not re.search(r"(?:§\d+|at \d{2}:\d{2}:\d{2})", sentence):
                errors.append(f"{requirement_id} has an unlabeled numeric target: {sentence.strip()[:140]}")

    minimums = {"P0": 8, "P1": 4, "P2": 4}
    for priority, minimum in minimums.items():
        if counts[priority] < minimum:
            errors.append(f"requirements contain {counts[priority]} {priority} items; expected at least {minimum}")

    quote_bank = root / "quote_bank" / "quote_bank.md"
    try:
        known_quotes = {int(value) for value in re.findall(r"(?m)^## §(\d+) — ", quote_bank.read_text(encoding="utf-8"))}
    except OSError as error:
        errors.append(f"cannot read quote bank: {error}")
        known_quotes = set()
    all_spec_text = "\n".join(texts.values())
    referenced_quotes = {int(value) for value in re.findall(r"§(\d+)", all_spec_text) if int(value) > 0}
    unknown = sorted(referenced_quotes - known_quotes)
    if unknown:
        errors.append(f"specifications reference unknown quote anchors: {unknown[:20]}")

    blueprint = texts.get("implementation_blueprint.md", "")
    for slice_number in range(9):
        if not re.search(rf"(?m)^## Slice {slice_number}\b", blueprint):
            errors.append(f"implementation blueprint is missing Slice {slice_number}")
    if "Every-slice verification" not in blueprint:
        errors.append("implementation blueprint is missing the every-slice verification gate")

    return errors, {"requirements": len(matches), "priorities": counts, "files": len(texts)}


def main() -> int:
    args = parse_args()
    errors, stats = validate(args.root.resolve())
    result = {"ok": not errors, "stats": stats, "errors": errors}
    if args.json:
        print(json.dumps(result, indent=2))
    elif errors:
        print("Product specification validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
    else:
        print(f"Product specification validation passed: {stats['requirements']} requirements.")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
