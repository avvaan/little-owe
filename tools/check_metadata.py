#!/usr/bin/env python3
"""Check the App Store listing draft against Apple's field limits.

Apple enforces these at submission, one field at a time, after a form has been filled
in - so a subtitle one character too long costs a round trip for no reason. This reads
the fenced blocks out of docs/APP_STORE.md and measures them.

Lengths are counted in characters the way App Store Connect counts them, which is
Unicode scalars rather than bytes.

    python3 tools/check_metadata.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "APP_STORE.md")

# (heading in the doc, limit, whether the block is one line)
FIELDS = [
    ("Promotional text", 170, False),
    ("Description", 4000, False),
    ("Keywords", 100, True),
    ("What's New in This Version", 4000, False),
]

# Fields that live in the table rather than in a fenced block.
TABLE_FIELDS = [("Name", 30), ("Subtitle", 30)]


def blocks(text):
    """The first fenced block under each `## heading`."""
    found = {}
    for match in re.finditer(r"^## (.+?)$", text, re.M):
        heading = match.group(1).strip()
        rest = text[match.end():]
        fence = re.search(r"^```\n(.*?)^```", rest, re.S | re.M)
        nxt = re.search(r"^## ", rest, re.M)
        if fence and (not nxt or fence.start() < nxt.start()):
            found[heading] = fence.group(1).strip("\n")
    return found


def table_value(text, field):
    m = re.search(rf"^\|\s*{re.escape(field)}\s*\|\s*`?([^`|]+?)`?\s*\|", text, re.M)
    return m.group(1).strip() if m else None


def main():
    text = open(DOC, encoding="utf-8").read()
    found = blocks(text)
    problems = []

    for field, limit in TABLE_FIELDS:
        value = table_value(text, field)
        if value is None:
            problems.append(f"{field}: not found in the App Information table")
            continue
        size = len(value)
        mark = "ok " if size <= limit else "!! "
        print(f"  {mark}{field:28} {size:5}/{limit}   {value}")
        if size > limit:
            problems.append(f"{field}: {size} characters, limit {limit}")

    for heading, limit, one_line in FIELDS:
        value = found.get(heading)
        if value is None:
            problems.append(f"{heading}: no fenced block under that heading")
            continue
        # The listing field is one paragraph; the doc wraps it for reading. Apple counts
        # what is pasted, so measure the unwrapped text for a single-line field.
        measured = value.replace("\n", " ") if one_line else value
        size = len(measured)
        mark = "ok " if size <= limit else "!! "
        print(f"  {mark}{heading:28} {size:5}/{limit}")
        if size > limit:
            problems.append(f"{heading}: {size} characters, limit {limit}")

        if heading == "Keywords":
            if " ," in measured or ", " in measured:
                problems.append("Keywords: a space next to a comma wastes a character each time")
            for word in measured.split(","):
                if not word.strip():
                    problems.append("Keywords: an empty keyword")

    print()
    if problems:
        print(f"{len(problems)} problem(s):")
        for p in problems:
            print(f"  {p}")
        return 1
    print("Every field is inside Apple's limit.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
