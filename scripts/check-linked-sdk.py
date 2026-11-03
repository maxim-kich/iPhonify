#!/usr/bin/env python3
"""Guard the SDK stamp that enables modern native AppKit control rendering."""
import re
import subprocess
import sys

output = subprocess.check_output(["xcrun", "vtool", "-show-build", sys.argv[1]], text=True)
match = re.search(r"^\s+sdk\s+(\d+(?:\.\d+)*)\s*$", output, re.MULTILINE)
if not match or int(match[1].split(".")[0]) < 26:
    raise SystemExit("The app must be linked against macOS SDK 26 or newer for native Liquid Glass controls")
print(f"PASS: native AppKit SDK {match[1]}")
