#!/usr/bin/env bash
# Bump the version line in pubspec.yaml (repo root: mobile/).
# Usage:
#   ./scripts/bump_version.sh           # increment build number after + (default)
#   ./scripts/bump_version.sh patch     # 1.2.3+N -> 1.2.4+1
#   ./scripts/bump_version.sh minor     # 1.2.3+N -> 1.3.0+1
#   ./scripts/bump_version.sh major     # 1.2.3+N -> 2.0.0+1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PUBSPEC="${MOBILE_DIR}/pubspec.yaml"

MODE="${1:-build}"

python3 - "${PUBSPEC}" "${MODE}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
mode = sys.argv[2]
text = path.read_text(encoding="utf-8")
m = re.search(r"^version:\s*([\d.]+)\+(\d+)\s*$", text, re.MULTILINE)
if not m:
    sys.stderr.write(
        f"{path}: expected a line like 'version: 1.0.0+1' (semver+build)\n"
    )
    sys.exit(1)

ver, build = m.group(1), int(m.group(2))
parts = [int(p) for p in ver.split(".")]
while len(parts) < 3:
    parts.append(0)
major, minor, patch = parts[0], parts[1], parts[2]

if mode == "build":
    build += 1
elif mode == "patch":
    patch += 1
    build = 1
elif mode == "minor":
    minor += 1
    patch = 0
    build = 1
elif mode == "major":
    major += 1
    minor = 0
    patch = 0
    build = 1
else:
    sys.stderr.write(f"Unknown mode {mode!r}. Use build|patch|minor|major.\n")
    sys.exit(1)

new_ver = f"{major}.{minor}.{patch}+{build}"
new_text = re.sub(
    r"^version:\s*[\d.]+\+\d+\s*$",
    f"version: {new_ver}",
    text,
    count=1,
    flags=re.MULTILINE,
)
path.write_text(new_text, encoding="utf-8")
print(new_ver)
PY
