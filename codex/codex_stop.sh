#!/bin/sh
# 현재 사용자의 모든 Codex 세션과 백그라운드 서버를 종료합니다.
# Codex 내부가 아닌 별도 터미널에서 실행하세요.
# 저장된 대화 기록은 삭제하지 않습니다.

if ! command -v pgrep >/dev/null 2>&1; then
  echo "오류: pgrep 명령이 필요합니다." >&2
  exit 1
fi

pids=$(pgrep -u "$(id -u)" -f '(^|/)(codex|codex-code-mode-host)([[:space:]]|$)')

if [ -z "$pids" ]; then
  echo "종료할 Codex 프로세스가 없습니다."
  exit 0
fi

echo "모든 Codex 세션과 백그라운드 서버를 종료합니다. PID:"
echo "$pids"

kill -TERM $pids 2>/dev/null || :
sleep 3

# 정상 종료되지 않은 프로세스는 강제 종료합니다.
failed=0
for pid in $pids; do
  if kill -0 "$pid" 2>/dev/null; then
    if ! kill -KILL "$pid" 2>/dev/null && kill -0 "$pid" 2>/dev/null; then
      echo "오류: PID $pid 종료에 실패했습니다." >&2
      failed=1
    fi
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "종료 요청 완료. codex resume으로 세션을 다시 선택하세요."
