#!/bin/sh
# Codex의 AGENTS.md(${CODEX_HOME:-~/.codex}/AGENTS.md)에 공통 지침(settings_prompt/*.txt)을
# 읽도록 하는 section을 추가합니다.
# 공통 지침 디렉터리 경로는 환경마다 다를 수 있으므로 실행할 때 정합니다.
# - 기본값: 이 스크립트 위치 기준 ../settings_prompt
# - 직접 지정: SHARED_PROMPT_DIR=/path/to/settings_prompt sh codex_prompt_setup.sh
# 이미 설정되어 있으면 기존 내용은 보존하고 경로 줄만 현재 경로로 갱신합니다.
# 경로 줄을 바꿀 때는 변경 전 파일을 <file>.bak.<timestamp>로 백업합니다.
set -eu

agents_dir="${CODEX_HOME:-${HOME:?HOME must be set}/.codex}"
agents_file="$agents_dir/AGENTS.md"
marker='<!-- shared-settings-prompt -->'
missing_txt_notice='- 해당 디렉터리와 하위 디렉터리에 `.txt` 파일이 하나도 없다면 사용자에게 그 사실을 알린다.'

# 공통 지침 디렉터리를 절대경로로 정한다. 존재하지 않는 경로는 AGENTS.md에 기록하지 않는다.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
prompt_dir="${SHARED_PROMPT_DIR:-$script_dir/../settings_prompt}"
if [ ! -d "$prompt_dir" ]; then
    printf '공통 지침 디렉터리를 찾을 수 없습니다: %s\n' "$prompt_dir" >&2
    printf 'SHARED_PROMPT_DIR=<settings_prompt 경로> 로 지정해 다시 실행하세요.\n' >&2
    exit 1
fi
prompt_dir=$(CDPATH= cd -- "$prompt_dir" && pwd)
case "$prompt_dir" in
    *'`'*) printf '경로에 backtick이 있어 사용할 수 없습니다: %s\n' "$prompt_dir" >&2; exit 1 ;;
esac

path_prefix='- 어떤 프로젝트에서든 작업을 시작하기 전에 `'
path_line="$path_prefix$prompt_dir"'/` 아래의 모든 `.txt` 파일을 하위 디렉터리까지 찾아 전체 내용을 읽는다.'

mkdir -p "$agents_dir"

# 이미 설정된 경우: 같은 section을 다시 추가하지 않고, 경로 줄과 누락된 안내만 갱신한다.
if [ -f "$agents_file" ] && grep -Fqx -- "$marker" "$agents_file"; then
    status='Already configured'
    if ! grep -Fqx -- "$path_line" "$agents_file"; then
        tmp="$agents_file.tmp.$$"
        # marker 이후 처음 나오는 경로 줄만 교체한다.
        if ! MARKER="$marker" PREFIX="$path_prefix" LINE="$path_line" awk '
            $0 == ENVIRON["MARKER"] { in_section = 1 }
            in_section && !done && index($0, ENVIRON["PREFIX"]) == 1 { print ENVIRON["LINE"]; done = 1; next }
            { print }
            END { exit !done }' "$agents_file" > "$tmp"; then
            rm -f "$tmp"
            printf '%s에서 공통 지침 경로 줄을 찾지 못했습니다. 직접 확인해 주세요.\n' "$agents_file" >&2
            exit 1
        fi
        cp "$agents_file" "$agents_file.bak.$(date +%Y%m%d%H%M%S)"
        cat "$tmp" > "$agents_file"
        rm -f "$tmp"
        status='Updated'
    fi
    if ! grep -Fqx -- "$missing_txt_notice" "$agents_file"; then
        printf '\n%s\n' "$missing_txt_notice" >> "$agents_file"
        status='Updated'
    fi
    printf '%s: %s\n' "$status" "$agents_file"
    printf 'Shared prompt dir: %s\n' "$prompt_dir"
    exit 0
fi

{
    printf '\n%s\n# 공통 작업 지침\n\n%s\n' "$marker" "$path_line"
    cat <<'EOF'
- 읽은 지침 중 현재 작업에 해당하는 지침을 준수한다.
- 디렉터리가 없거나 파일을 읽을 수 없다면 사용자에게 그 사실을 알리고, 해당 지침을 읽었다고 가정하지 않는다.
- 세션 시작 시 공통 .txt 파일을 경로순으로 전체 읽는다. 같은 세션에서
  내용이 바뀌지 않았다면 매 요청마다 중복해서 읽을 필요는 없다.
- 공통 지침은 해당 범위에만 적용하며 기존 agent 역할과 작업 분담을 대체하지 않는다.
- 관련 작업을 subagent에 위임할 때 적용할 공통 정책의 위치와
  확정된 프로젝트별 설정을 전달한다.
EOF
    printf '%s\n' "$missing_txt_notice"
} >> "$agents_file"

printf 'Configured: %s\n' "$agents_file"
printf 'Shared prompt dir: %s\n' "$prompt_dir"
