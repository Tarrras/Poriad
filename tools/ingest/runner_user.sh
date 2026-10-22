#!/bin/bash
# Self-hosted runner в окремому користувачі macOS (docs/security-audit-2026-10-22.md, H1). Репозиторій публічний:
# job із PR форка, якщо його колись схвалити, виконується на цьому Mac. Під окремим користувачем він не бачить вашого
# дому — .env, ~/.keys, ~/.ssh, токенів gh і supabase. Секрети самого runner-а (SUPABASE_DB_URL, токен Claude) такий
# job усе одно отримав би, тож PR від сторонніх і далі не схвалювати.
#
# Запуск — від себе, з кореня репозиторію: tools/ingest/runner_user.sh. sudo спитає пароль адміністратора.
# Потрібен `gh`, увійдений у GitHub з правом адміністратора репозиторію (токени реєстрації runner-а).
set -euo pipefail

R=poriad-runner
RH=/Users/$R
REPO=Tarrras/Poriad
NAME=MacBook-Pro-Taras
OLD=$HOME/actions-runner
NEW=$RH/actions-runner
PLIST=/Library/LaunchDaemons/app.poriad.runner.plist

# 1. Ваш дім — лише вам. Він drwxr-x--- з групою staff, а в staff — кожен локальний користувач: без цього новий
#    користувач прочитав би .env (644) у StudioProjects.
chmod 700 "$HOME"

# 2. Користувач без прав адміністратора, схований з екрана входу. Пароль випадковий: входити ним не треба.
if ! id "$R" >/dev/null 2>&1; then
  sudo sysadminctl -addUser "$R" -fullName "Poriad runner" -password "$(openssl rand -base64 24)" -home "$RH"
  sudo createhomedir -c -u "$R" >/dev/null
  sudo dscl . -create "/Users/$R" IsHidden 1
fi
sudo chmod 700 "$RH"

# 3. Залежності обходу — свої в нового користувача: psycopg (як у вас) і Claude Code для аналізу прогону.
sudo -u "$R" -H /usr/bin/python3 -m pip install --user --quiet 'psycopg[binary]==3.2.13'
# PATH явно: sudo скидає його до системного, і npm не знайшов би node з Homebrew.
sudo -u "$R" -H env PATH=/opt/homebrew/bin:/usr/bin:/bin npm install -g --silent --prefix "$RH/.npm-global" @anthropic-ai/claude-code

# 4. Старий runner: служба й реєстрація на GitHub. Тека лишається — з неї копіюємо бінарники й робочу теку.
if [ -f "$OLD/.runner" ]; then
  (cd "$OLD" && { ./svc.sh stop || true; ./svc.sh uninstall || true; } \
    && ./config.sh remove --token "$(gh api -X POST "repos/$REPO/actions/runners/remove-token" -q .token)")
fi

# 5. Новий runner — ті самі бінарники без старої реєстрації. Робоча тека — цілком, з .git: checkout стирає теку,
#    що не є репозиторієм, а з нею й кеш обходу (badseller без кешу читається 43 хв).
sudo mkdir -p "$NEW"
sudo rsync -a --exclude _diag --exclude .runner --exclude .credentials --exclude .credentials_rsaparams \
  --exclude .service --exclude .path --exclude .env "$OLD/" "$NEW/"
# Невідстежений файл у робочій теці пережив би checkout з clean: false — не переносимо.
sudo rm -f "$NEW/_work/Poriad/Poriad/.claude/settings.local.json"
echo "$RH/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" | sudo tee "$NEW/.path" >/dev/null
sudo chown -R "$R" "$NEW"
TOKEN=$(gh api -X POST "repos/$REPO/actions/runners/registration-token" -q .token)
sudo -u "$R" -H bash -c "cd '$NEW' && ./config.sh --unattended --replace --url https://github.com/$REPO --token '$TOKEN' --name '$NAME'"

# 6. Служба — LaunchDaemon від імені нового користувача: стартує з системою, без його входу (svc.sh ставить
#    LaunchAgent, який чекає входу в сесію).
sudo tee "$PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>app.poriad.runner</string>
  <key>ProgramArguments</key><array><string>$NEW/runsvc.sh</string></array>
  <key>UserName</key><string>$R</string>
  <key>WorkingDirectory</key><string>$NEW</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$NEW/_diag/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$NEW/_diag/launchd.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ACTIONS_RUNNER_SVC</key><string>1</string>
    <key>HOME</key><string>$RH</string>
  </dict>
</dict>
</plist>
EOF
sudo mkdir -p "$NEW/_diag" && sudo chown "$R" "$NEW/_diag"
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"

sleep 5
gh api "repos/$REPO/actions/runners" -q '.runners[] | .name + " " + .status'
echo "Готово. Стару теку можна прибрати: rm -rf $OLD"
