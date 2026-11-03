#!/usr/bin/env python3
"""Check the candidate public file set without printing sensitive matches."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
names = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    cwd=root, text=True).split("\0")
patterns = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}"),
    re.compile(r"AKIA[A-Z0-9]{16}"),
    re.compile(r"/(?:Users|home)/[^\s/]+/"),
]
errors = []
count = 0
for name in sorted(set(names)):
    if not name or not (root / name).is_file():
        continue
    path = pathlib.Path(name)
    if path.parts[0] in {".local", ".build", "build", "dist", ".nimbalyst"}:
        errors.append(f"{name}: local-only directory")
    if path.name.startswith(".env") and path.name != ".env.example":
        errors.append(f"{name}: environment file")
    if path.suffix.lower() in {".p12", ".p8", ".pem", ".key", ".log", ".mov", ".mp4"}:
        errors.append(f"{name}: excluded artifact or credential format")
    data = (root / name).read_bytes()
    if len(data) > 10_000_000:
        errors.append(f"{name}: unexpected large file")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        continue
    if any(pattern.search(text) for pattern in patterns):
        errors.append(f"{name}: possible secret or machine-specific path; inspect locally")
    count += 1
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print(f"PASS: {count} public text files checked; no detected local artifacts, private-key material, tokens, or machine paths")
