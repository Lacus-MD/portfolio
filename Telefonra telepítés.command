#!/bin/zsh
# Lefordítja és a csatlakoztatott iPhone-ra telepíti a Portfólió appot.
# FIGYELEM: az ELSŐ telepítést érdemes Xcode-ból (⌘R) elvégezni — a provisioning
# párbeszédeit csak ott lehet kattintva jóváhagyni. Utána ez a script elég.
cd "$(dirname "$0")"

# A devicectl azonosítója NEM ugyanaz, mint az xcodebuild -destination id-je
# (a devicectl saját UUID-t ad, az xcodebuild a hardveres ECID-et várja).
# Ezért nem is próbáljuk összekötni: generikus iOS-célra fordítunk, és
# külön telepítünk a devicectl saját azonosítójával.
#
# A szűrésnél `grep -v unavailable` KELL: az "unavailable" tartalmazza az
# "available" szót, így a puszta `grep available` a le sem csatlakoztatott
# telefont is kiválasztaná.
DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
  | grep -i physical | grep -i iphone | grep -vi unavailable \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
  | head -1)

if [ -z "$DEVICE_ID" ]; then
  echo "Nincs elérhető iPhone."
  echo "Csatlakoztasd kábellel, oldd fel a zárat, és fogadd el a"
  echo "'Megbízom ebben a gépben' kérdést. Jelenlegi állapot:"
  echo
  xcrun devicectl list devices | grep -i physical
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
