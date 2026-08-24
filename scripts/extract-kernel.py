#!/usr/bin/env python3
"""Extract one versioned triangulated-kernel block from Markdown."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


MARKER = re.compile(
    r"(?ms)^<!-- TRIANGULATED_KERNEL_START (v\d+\.\d+) -->\n"
    r"(.*?)"
    r"^<!-- TRIANGULATED_KERNEL_END \1 -->$"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Markdown file containing the kernel")
    parser.add_argument("--output", type=Path, help="write the extracted block to this file")
    return parser.parse_args()


def extract(text: str) -> str:
    matches = list(MARKER.finditer(text))
    if len(matches) != 1:
        raise ValueError(f"expected exactly one versioned kernel block, found {len(matches)}")
    return matches[0].group(0) + "\n"


def main() -> int:
    args = parse_args()
    try:
        block = extract(args.source.read_text(encoding="utf-8"))
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(block, encoding="utf-8")
        else:
            sys.stdout.write(block)
    except (OSError, ValueError) as error:
        print(f"kernel extraction failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
