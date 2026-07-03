#!/bin/zsh
# Genera dist/Marcus.app y dist/Marcus-X.Y.Z.dmg listos para usar.
#
# Uso:  scripts/build-dmg.sh
#
# El resultado va firmado ad-hoc: funciona sin avisos en esta máquina.
# Para distribuir a otros Macs hace falta firma Developer ID + notarización
# (ver DEPLOY.md, sección "Pendiente").

set -euo pipefail

cd "$(dirname "$0")/.."

PLIST="Sources/Marcus/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
APP="dist/Marcus.app"
DMG="dist/Marcus-${VERSION}.dmg"

echo "==> Compilando Marcus ${VERSION} (release, binario universal)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Marcus"

echo "==> Ensamblando ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Marcus"
cp "$PLIST" "$APP/Contents/Info.plist"
cp Resources/marcus.icns "$APP/Contents/Resources/marcus.icns"
# Bundles de recursos de SwiftPM (String Catalogs — i18n, D14).
# Bundle.module los busca en Contents/Resources del .app.
for bundle in "$(dirname "$BIN")"/Marcus_*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Firmando (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Creando ${DMG}"
STAGING="dist/.dmg-staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Marcus" -srcfolder "$STAGING" -format UDZO -ov "$DMG" > /dev/null
rm -rf "$STAGING"

echo ""
echo "Listo:"
echo "  ${APP}   — doble clic para usarla, o arrástrala a /Applications"
echo "  ${DMG}"
