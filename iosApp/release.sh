#!/bin/bash
# Prod-реліз iOS: збирає Release-Prod і вантажить в App Store Connect (звідти ж бере TestFlight).
#   iosApp/release.sh              підняти номер збірки, закомітити його, зібрати, завантажити
#   iosApp/release.sh --no-upload  лише зібрати .ipa у .build/release/export, номер не чіпати
# Завантаження йде через Apple ID, авторизований у Xcode → Settings → Apple Accounts.
set -euo pipefail
cd "$(dirname "$0")"

UPLOAD=1; [[ "${1:-}" == "--no-upload" ]] && UPLOAD=0
PLIST=Poruch/Info.plist
OUT=.build/release
pb() { /usr/libexec/PlistBuddy -c "$1" "$2"; }

if (( UPLOAD )); then
  # Номер збірки в App Store Connect незворотний, тож збірка мусить відповідати коміту.
  [[ -z "$(git status --porcelain)" ]] || { echo "Є незакомічені зміни. Закомітьте або сховайте їх." >&2; exit 1; }
  pb "Set :CFBundleVersion $(( $(pb 'Print :CFBundleVersion' $PLIST) + 1 ))" $PLIST
  git commit -qm "chore(ios): збірка $(pb 'Print :CFBundleVersion' $PLIST)" $PLIST
fi
echo "==> $(pb 'Print :CFBundleShortVersionString' $PLIST) ($(pb 'Print :CFBundleVersion' $PLIST)) з $(git rev-parse --short HEAD)"

rm -rf $OUT && mkdir -p $OUT
xcodebuild archive -project Poruch.xcodeproj -scheme Poruch-Prod -configuration Release-Prod \
  -destination 'generic/platform=iOS' -archivePath $OUT/Poriad.xcarchive -allowProvisioningUpdates \
  > $OUT/archive.log 2>&1 || { grep -E " error:|FAILED" $OUT/archive.log >&2; exit 1; }

# Єдина перевірка, без якої вантажити не можна: у стор не має поїхати dev.
APP=$OUT/Poriad.xcarchive/Products/Applications/Poruch.app
[[ "$(pb 'Print :APP_ENV' $APP/Info.plist)" == PROD && "$(pb 'Print :CFBundleIdentifier' $APP/Info.plist)" == app.poriad.ios \
   && "$(pb 'Print :SUPABASE_URL' $APP/Info.plist)" == https://tzdogzdvctlumsqlqskr.supabase.co ]] \
  || { echo "Архів не prod, зупиняюсь." >&2; exit 1; }

cat > $OUT/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$( (( UPLOAD )) && echo upload || echo export )</string>
<key>teamID</key><string>QTYQMJ94D2</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath $OUT/Poriad.xcarchive -exportPath $OUT/export \
  -exportOptionsPlist $OUT/ExportOptions.plist -allowProvisioningUpdates \
  > $OUT/export.log 2>&1 || { grep -iE "error|FAILED" $OUT/export.log >&2; exit 1; }

(( UPLOAD )) && echo "==> Завантажено. Обробка в App Store Connect триває 10–30 хв." \
             || echo "==> Готово: $PWD/$OUT/export/Poruch.ipa"
