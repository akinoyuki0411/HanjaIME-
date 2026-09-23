#!/usr/bin/env python3
"""Calculate the next release; the patch component is limited to 0..9."""
import re
import sys

def next_version(version):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.[0-9]", version):
        raise ValueError("Expected major.minor.patch with patch between 0 and 9")
    major, minor, patch = map(int, version.split("."))
    minor, patch = (minor + 1, 0) if patch == 9 else (minor, patch + 1)
    return f"{major}.{minor}.{patch}"

if __name__ == "__main__":
    try:
        print(next_version(sys.argv[1]))
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
