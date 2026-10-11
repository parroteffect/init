#!/usr/bin/env bash
# Claude Code status line 설정: 모델 | effort | 주간 남은 사용량 | context 사용량
# 사용법: bash setup_statusline.sh
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT="$CLAUDE_DIR/statusline.py"
SETTINGS="$CLAUDE_DIR/settings.json"

command -v python3 >/dev/null || { echo "python3가 필요합니다." >&2; exit 1; }
mkdir -p "$CLAUDE_DIR"

# 1) status line 렌더링 스크립트 작성
cat > "$SCRIPT" <<'PY'
#!/usr/bin/env python3
import json, sys, time

try:
    d = json.load(sys.stdin)
except Exception:
    d = {}

RESET, DIM = "\033[0m", "\033[2m"

def color(pct_used):
    # 사용률 기준 색: <50 초록, <80 노랑, 그 이상 빨강
    if pct_used is None:
        return ""
    return "\033[32m" if pct_used < 50 else "\033[33m" if pct_used < 80 else "\033[31m"

def until(ts):
    if not ts:
        return ""
    s = max(0, int(ts - time.time()))
    d_, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
    return f"{d_}d{h}h" if d_ else f"{h}h{m}m"

parts = []

model = (d.get("model") or {}).get("display_name") or "?"
parts.append(f"\033[36m{model}\033[0m")

effort = (d.get("effort") or {}).get("level")
parts.append(f"effort:{effort}" if effort else f"{DIM}effort:-{RESET}")

week = ((d.get("rate_limits") or {}).get("seven_day") or {})
wu = week.get("used_percentage")
if wu is not None:
    left = 100 - wu
    r = until(week.get("resets_at"))
    parts.append(f"week left:{color(wu)}{left:.0f}%{RESET}" + (f"{DIM} (reset {r}){RESET}" if r else ""))
else:
    parts.append(f"{DIM}week left:-{RESET}")

cw = d.get("context_window") or {}
cu = cw.get("used_percentage")
if cu is not None:
    size = cw.get("context_window_size")
    sz = f"/{size // 1000}k" if size else ""
    parts.append(f"ctx:{color(cu)}{cu:.0f}%{RESET}{DIM}{sz}{RESET}")
else:
    parts.append(f"{DIM}ctx:-{RESET}")

print(" | ".join(parts))
PY
chmod +x "$SCRIPT"

# 2) settings.json에 statusLine 등록 (기존 설정 유지, 백업 생성)
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
python3 - "$SETTINGS" "$SCRIPT" <<'PY'
import json, os, sys
path, script = sys.argv[1], sys.argv[2]
cfg = {}
if os.path.exists(path):
    with open(path) as f:
        txt = f.read().strip()
        cfg = json.loads(txt) if txt else {}
cfg["statusLine"] = {"type": "command", "command": f"python3 {script}", "padding": 0}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

echo "✓ status line 설정 완료: $SCRIPT"
echo "  미리보기:"
echo '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"rate_limits":{"seven_day":{"used_percentage":41.2,"resets_at":'$(( $(date +%s) + 300000 ))'}},"context_window":{"used_percentage":8,"context_window_size":1000000}}' \
  | python3 "$SCRIPT"
echo "  (다음 응답부터 반영됩니다. 안 보이면 Claude Code를 재시작하세요)"
