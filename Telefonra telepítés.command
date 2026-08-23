#!/bin/zsh
# Lefordítja és a csatlakoztatott iPhone-ra telepíti a Portfólió appot.
# FIGYELEM: az ELSŐ telepítést érdemes Xcode-ból (⌘R) elvégezni — a provisioning
# párbeszédeit csak ott lehet kattintva jóváhagyni. Utána ez a script elég.
cd "$(dirname "$0")"

# A devicectl azonosítója NEM ugyanaz, mint az xcodebuild -destination id-je
# (a devicectl saját UUID-t ad, az xcodebuild a hardveres ECID-et várja).
# A telepítőt a saját telefonhoz rögzítjük. Az „első elérhető iPhone" veszélyes:
# ha a saját készülék nincs a közelben, csendben egy másik családi telefonra
# tehetné fel az appot.
DEVICE_ID="F1C6000E-90D0-5D59-ABAC-232B64DE0DAF"
DEVICE_LINE=$(xcrun devicectl list devices 2>/dev/null | grep -F "$DEVICE_ID")

# Az "unavailable" tartalmazza az "available" szót, ezért ezt külön kell
# kizárni, nem elég egyetlen `grep available`.
if [ -z "$DEVICE_LINE" ] || [[ "$DEVICE_LINE" == *unavailable* ]] \
   || [[ "$DEVICE_LINE" != *available* ]]; then
  echo "A saját iPhone jelenleg nem elérhető."
  echo "Csatlakoztasd kábellel, oldd fel a zárat, és fogadd el a"
  echo "'Megbízom ebben a gépben' kérdést. Jelenlegi állapot:"
  echo
  xcrun devicectl list devices | grep -F "$DEVICE_ID"
  exit 1
fi
echo "Eszköz: $DEVICE_ID"

command -v xcodegen >/dev/null && xcodegen generate

# -allowProvisioningUpdates: enélkül a widget-extension app-idjét és az
# App Groupot nem regisztrálja automatikusan, és a build elhasal.
xcodebuild -project Portfolio.xcodeproj -scheme Portfolio \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_COVERAGE_MAPPING=NO \
  build || exit 1

# Pontosan a frissen elkészült, optimalizált csomagot telepítjük. A `find`
# korábban a build mappában maradt Debug appot is kiválaszthatta, így még egy
# sikeres Release fordítás után sem volt biztos, melyik került a telefonra.
APP="build/Build/Products/Release-iphoneos/Portfolio.app"
[ ! -d "$APP" ] && { echo "Nem találom a Release appot: $APP"; exit 1; }

xcrun devicectl device install app --device "$DEVICE_ID" "$APP" || exit 1
echo
echo "Kész. A widgetet kézzel kell hozzáadni:"
echo "  nyomd hosszan a kezdőképernyőt → '+' → keress rá: Portfólió"
