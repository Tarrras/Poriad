#!/bin/bash
# Фонова сесія Claude Code з аналізом щойно завершеного обходу (викликає .github/workflows/ingest.yml).
#   TARGET=prod|dev TESTS=<outcome> DUMP=<outcome> RUN_URL=<посилання> tools/ingest/analyze_run.sh
# Сесія без інструментів і без доступу до бази: дані їй дає tools/ingest/run_stats.py. Результат:
# `claude agents`, `claude attach <id>`, `claude logs <id>`.
set -euo pipefail
cd "$(dirname "$0")/../.."
# Служба runner-а стартує з мінімальним PATH.
export PATH="$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Токен із секрету міг прийти з переносом рядка (скопійований з терміналу): CLI тоді не входить.
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  export CLAUDE_CODE_OAUTH_TOKEN="$(printf %s "$CLAUDE_CODE_OAUTH_TOKEN" | tr -d '[:space:]')"
fi

target="${TARGET:-prod}"

# Дані збирає скрипт (лише SELECT), а сесія бачить їх текстом і сама до бази не ходить: на runner нема ні
# OAuth до Supabase MCP, ні потреби давати моделі доступ до прод-бази.
stats="$(python3 -m tools.ingest.run_stats --env "$target" 2>&1)" || stats="НЕ ВДАЛОСЯ ЗІБРАТИ ДАНІ:
${stats}"

prompt="$(cat tools/ingest/analyst_prompt.md)

Контекст:
- середовище: ${target}
- крок «тести ingest»: ${TESTS:-невідомо}; крок «дамп у базу»: ${DUMP:-невідомо}
- запуск: ${RUN_URL:-вручну}

Дані з бази:
${stats}"

# RUNNER_TRACKING_ID="" — інакше runner вбиває дочірні процеси кроку, і сесія не доживе до кінця job.
# --tools "" і порожній набір MCP: сесія лише читає текст і відповідає. `--` — перелік жадібний.
RUNNER_TRACKING_ID="" claude --bg --no-chrome --strict-mcp-config --tools "" -- "$prompt"
