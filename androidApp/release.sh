#!/bin/bash
# Prod-реліз Android: збирає prodRelease AAB і вантажить у Google Play (production) з примітками до випуску.
#   androidApp/release.sh              підняти номер збірки, закомітити його, зібрати, завантажити
#   androidApp/release.sh --no-upload  лише зібрати .aab, номер не чіпати
# Примітки — рядок «**Play → примітки до випуску (<versionName>, …):**» зі store/listing.md.
# Завантаження йде від сервісного акаунта Google Cloud із доступом у Play Console → Users and permissions;
# JSON-ключ — ~/.poriad/play-service-account.json або шлях у PLAY_KEY.
set -euo pipefail
cd "$(dirname "$0")/.."

UPLOAD=1; [[ "${1:-}" == "--no-upload" ]] && UPLOAD=0
KEY=${PLAY_KEY:-$HOME/.poriad/play-service-account.json}
AAB=androidApp/build/outputs/bundle/prodRelease/androidApp-prod-release.aab
LOG=androidApp/build/release.log
VER=$(sed -n 's/.*versionName = "\(.*\)"/\1/p' androidApp/build.gradle.kts)
code() { sed -n 's/^poriad.versionCode=//p' gradle.properties; }

if (( UPLOAD )); then
  [[ -f "$KEY" ]] || { echo "Немає ключа сервісного акаунта: $KEY" >&2; exit 1; }
  NOTES=$(sed -n "s/^\*\*Play → примітки до випуску ($VER[,)][^*]*\*\* //p" store/listing.md)
  [[ -n "$NOTES" ]] || { echo "У store/listing.md немає приміток Play для $VER." >&2; exit 1; }
  (( $(printf %s "$NOTES" | LC_ALL=en_US.UTF-8 wc -m) <= 500 )) || { echo "Примітки довші за 500 знаків." >&2; exit 1; }
  # Номер збірки в Play незворотний, тож збірка мусить відповідати коміту.
  [[ -z "$(git status --porcelain)" ]] || { echo "Є незакомічені зміни. Закомітьте або сховайте їх." >&2; exit 1; }
  sed -i '' "s/^poriad.versionCode=.*/poriad.versionCode=$(( $(code) + 1 ))/" gradle.properties
  git commit -qm "chore(android): збірка $(code)" gradle.properties
fi
echo "==> $VER ($(code)) з $(git rev-parse --short HEAD)"

mkdir -p androidApp/build
./gradlew -q :androidApp:bundleProdRelease > $LOG 2>&1 || { grep -E "^e:|FAILED|What went wrong" -A3 $LOG >&2; exit 1; }

# Єдина перевірка, без якої вантажити не можна: у стор не має поїхати dev.
DEX=$(unzip -p $AAB 'base/dex/*.dex' | strings)
grep -q tzdogzdvctlumsqlqskr <<< "$DEX" && ! grep -q ojadoyxeahepycpmjuvf <<< "$DEX" \
  || { echo "AAB не prod, зупиняюсь." >&2; exit 1; }

(( UPLOAD )) || { echo "==> Готово: $PWD/$AAB"; exit 0; }

uv run -q --no-project --with google-auth --with requests python - "$KEY" "$AAB" "$NOTES" <<'PY'
import sys
from google.auth.transport.requests import AuthorizedSession
from google.oauth2.service_account import Credentials

key, aab, notes = sys.argv[1:]
s = AuthorizedSession(Credentials.from_service_account_file(key, scopes=["https://www.googleapis.com/auth/androidpublisher"]))
app = "androidpublisher.googleapis.com/{}androidpublisher/v3/applications/app.poriad.android/edits"
api, upload = "https://" + app.format(""), "https://" + app.format("upload/")

def ok(r):
    if not r.ok: sys.exit(f"Play {r.status_code}: {r.text}")
    return r.json()

edit = ok(s.post(api))["id"]
with open(aab, "rb") as f:
    code = ok(s.post(f"{upload}/{edit}/bundles?uploadType=media", data=f,
                     headers={"Content-Type": "application/octet-stream"}, timeout=900))["versionCode"]
ok(s.put(f"{api}/{edit}/tracks/production", json={"track": "production", "releases": [
    {"versionCodes": [str(code)], "status": "completed", "releaseNotes": [{"language": "uk", "text": notes}]}]}))
ok(s.post(f"{api}/{edit}:commit"))
PY
echo "==> Завантажено в production. Перевірка Google зазвичай триває від кількох годин до кількох днів."
