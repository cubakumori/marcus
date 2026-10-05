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

# Las acciones de Atajos (App Intents) necesitan que el compilador emita los
# valores constantes de las declaraciones y que la herramienta de Apple los
# convierta en Metadata.appintents dentro del .app — lo que Xcode hace solo
# y SwiftPM no (ver DEPLOY.md). Los flags no cambian el binario.
TOOLCHAIN="$(dirname "$(dirname "$(xcrun --find swiftc)")")"
PROTOCOLS="$TOOLCHAIN/share/swift/SwiftConstantValues/AppIntents.json"
CONST_FLAGS=(-Xswiftc -emit-const-values -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$PROTOCOLS")

echo "==> Compilando Marcus ${VERSION} (release, binario universal)"
swift build -c release --arch arm64 --arch x86_64 "${CONST_FLAGS[@]}"
BIN="$(swift build -c release --arch arm64 --arch x86_64 "${CONST_FLAGS[@]}" --show-bin-path)/Marcus"

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
# Títulos localizados del menú Servicios (ServicesMenu.strings): macOS los
# busca en los .lproj del propio .app, no en los bundles de SwiftPM.
for lproj in Resources/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done
# Diccionario AppleScript (Info.plist: OSAScriptingDefinition).
cp Resources/Marcus.sdef "$APP/Contents/Resources/Marcus.sdef"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Metadatos de las acciones de Atajos"
CONST_LIST="$(mktemp)"
SOURCE_LIST="$(mktemp)"
find .build -name "*.swiftconstvalues" -path "*/Marcus.build/*" -path "*/arm64/*" > "$CONST_LIST"
find Sources/Marcus -name "*.swift" | sed "s|^|$PWD/|" > "$SOURCE_LIST"
[ -s "$CONST_LIST" ] || { echo "No hay .swiftconstvalues del módulo Marcus"; exit 1; }
xcrun appintentsmetadataprocessor \
  --output "$APP/Contents/Resources" \
  --toolchain-dir "$TOOLCHAIN/.." \
  --module-name Marcus \
  --sdk-root "$(xcrun --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
  --platform-family macOS \
  --deployment-target 14.0 \
  --target-triple arm64-apple-macos14.0 \
  --source-file-list "$SOURCE_LIST" \
  --swift-const-vals-list "$CONST_LIST" \
  --force --quiet-warnings > /dev/null
rm -f "$CONST_LIST" "$SOURCE_LIST"
scripts/verify-intents.sh "$APP"

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
