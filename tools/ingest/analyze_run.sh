#!/bin/bash
# Фонова сесія Claude Code з аналізом щойно завершеного обходу (викликає .github/workflows/ingest.yml).
#   TARGET=prod|dev TESTS=<outcome> DUMP=<outcome> RUN_URL=<посилання> tools/ingest/analyze_run.sh
# Сесія лише читає базу (`execute_sql` MCP; prod-сервер у .mcp.json зі `read_only=true`) і нічого не
# пише: Edit/Write/Bash заборонені, тож їй нема на що чекати дозволу. Результат: `claude agents`,
# `claude attach <id>`, `claude logs <id>`.
set -euo pipefail
cd "$(dirname "$0")/../.."
# Служба runner-а стартує з мінімальним PATH.
export PATH="$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

target="${TARGET:-prod}"
server=supabase
[ "$target" = dev ] && server=supabase-dev

prompt="$(cat tools/ingest/analyst_prompt.md)

Контекст:
- середовище: ${target}; MCP-сервер для запитів: ${server} (інструмент mcp__${server}__execute_sql)
- крок «тести ingest»: ${TESTS:-невідомо}; крок «дамп у базу»: ${DUMP:-невідомо}
- запуск: ${RUN_URL:-вручну}"

# RUNNER_TRACKING_ID="" — інакше runner вбиває дочірні процеси кроку, і сесія не доживе до кінця job.
RUNNER_TRACKING_ID="" claude --bg \
  --strict-mcp-config --mcp-config .mcp.json \
  --allowedTools "mcp__${server}__execute_sql,Read" \
  --disallowedTools "Edit,Write,NotebookEdit,Bash" \
  -- "$prompt"      # `--`: списки інструментів жадібні й інакше проковтнули б промпт
