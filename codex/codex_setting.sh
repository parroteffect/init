#!/usr/bin/env bash
set -euo pipefail

config="${CODEX_HOME:-$HOME/.codex}/config.toml"
mkdir -p "$(dirname "$config")"

python3 - "$config" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
content = path.read_text() if path.exists() else ""
setting = 'status_line = ["model-with-reasoning", "five-hour-limit", "weekly-limit", "context-remaining"]'
section = re.search(r'(?m)^\[tui\]\s*$', content)
if section:
    end = re.search(r'(?m)^\[', content[section.end():])
    stop = section.end() + end.start() if end else len(content)
    body = content[section.end():stop]
    body, count = re.subn(r'(?m)^status_line\s*=.*$', setting, body, count=1)
    if not count:
        body = '\n' + setting + body
    content = content[:section.end()] + body + content[stop:]
else:
    content = '[tui]\n' + setting + '\n\n' + content
path.write_text(content)
print(f"Updated {path}")
PY
