# DEPLOY — Build de release y distribución

Marcus es una app de escritorio para macOS: aquí "desplegar" significa
producir un `Marcus.app` distribuible. La estrategia de distribución está
decidida en el [ROADMAP](ROADMAP.md) (D8 y D9): distribución directa
notarizada con Sparkle para actualizaciones; el App Store se evaluará después.

## Estado actual

Durante las Fases 0–1 no hay releases públicas. El binario se construye con
SwiftPM y el Info.plist va embebido en el ejecutable, así que para desarrollo
basta con:

```sh
swift build -c release
.build/release/Marcus
```

## Generar Marcus.app (sin firmar)

Un bundle mínimo para uso local se ensambla a mano a partir del binario de
release:

```sh
swift build -c release
APP=dist/Marcus.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp .build/release/Marcus "$APP/Contents/MacOS/Marcus"
cp Sources/Marcus/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
open dist   # arrastrar Marcus.app a /Applications si se quiere
```

`dist/` está en `.gitignore`; los bundles no se versionan.

## Checklist de release

1. `swift test` en verde.
2. Presupuestos de rendimiento del ROADMAP verificados (cuando existan los
   tests de rendimiento, serán bloqueantes).
3. Actualizar `CFBundleShortVersionString` e incrementar `CFBundleVersion`
   en [Sources/Marcus/Info.plist](Sources/Marcus/Info.plist).
4. Mover lo hecho de `[Sin publicar]` a la nueva versión en
   [CHANGELOG.md](CHANGELOG.md) con la fecha del día.
5. Commit de release y tag anotado: `git tag -a vX.Y.Z -m "Marcus X.Y.Z"`.
6. Generar el bundle (apartado anterior) y prueba de humo manual: abrir,
   editar, guardar, buscar, cerrar y reabrir (sesión restaurada).

## Pendiente (antes de la primera release pública)

Estos pasos se documentarán en detalle cuando toquen (previsiblemente al
final de la Fase 2):

- **Firma**: certificado Developer ID Application y `codesign` con hardened
  runtime. Requiere migrar de Info.plist embebido a bundle real firmado
  (posiblemente con un proyecto Xcode o xcodegen — ver D8).
- **Notarización**: `xcrun notarytool submit` + `xcrun stapler staple`.
- **Actualizaciones**: integración de Sparkle 2 (appcast firmado, clave EdDSA).
- **CI**: pipeline que ejecute build + tests + presupuestos de rendimiento
  en cada push y produzca el artefacto de release en cada tag.
