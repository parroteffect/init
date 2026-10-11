#!/bin/sh
set -eu

agents_dir="${CODEX_HOME:-${HOME:?HOME must be set}/.codex}"
agents_file="$agents_dir/AGENTS.md"
marker='<!-- shared-settings-prompt -->'
missing_txt_notice='- 해당 디렉터리와 하위 디렉터리에 `.txt` 파일이 하나도 없다면 사용자에게 그 사실을 알린다.'

mkdir -p "$agents_dir"

# Preserve existing instructions and avoid adding the same section twice.
if [ -f "$agents_file" ] && grep -Fqx "$marker" "$agents_file"; then
    if ! grep -Fqx -- "$missing_txt_notice" "$agents_file"; then
        printf '\n%s\n' "$missing_txt_notice" >> "$agents_file"
        printf 'Updated: %s\n' "$agents_file"
        exit 0
    fi
    printf 'Already configured: %s\n' "$agents_file"
    exit 0
fi

cat >> "$agents_file" <<'EOF'

<!-- shared-settings-prompt -->
# 공통 작업 지침

- 어떤 프로젝트에서든 작업을 시작하기 전에 `/workspace/_nas/_shared/init/settings_prompt/` 아래의 모든 `.txt` 파일을 하위 디렉터리까지 찾아 전체 내용을 읽는다.
- 읽은 지침 중 현재 작업에 해당하는 지침을 준수한다.
- 디렉터리가 없거나 파일을 읽을 수 없다면 사용자에게 그 사실을 알리고, 해당 지침을 읽었다고 가정하지 않는다.
- 세션 시작 시 공통 .txt 파일을 경로순으로 전체 읽는다. 같은 세션에서
  내용이 바뀌지 않았다면 매 요청마다 중복해서 읽을 필요는 없다.
- 공통 지침은 해당 범위에만 적용하며 기존 agent 역할과 작업 분담을 대체하지 않는다.
- 관련 작업을 subagent에 위임할 때 적용할 공통 정책의 위치와
  확정된 프로젝트별 설정을 전달한다.
EOF
printf '%s\n' "$missing_txt_notice" >> "$agents_file"

printf 'Configured: %s\n' "$agents_file"
