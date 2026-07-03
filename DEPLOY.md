# DEPLOY — Build de release y distribución

Marcus es una app de escritorio para macOS: aquí "desplegar" significa
producir un `Marcus.app` distribuible. La estrategia de distribución está
decidida en el [ROADMAP](ROADMAP.md) (D8 y D9): distribución directa
notarizada con Sparkle para actualizaciones; el App Store se evaluará después.

## Estado actual

Hay releases etiquetadas (última: v0.3.0) con `.app` y `.dmg` firmados
ad-hoc — usables en la máquina donde se compilan, pero todavía no aptas para
distribución pública sin fricción (ver "Pendiente"). El binario se construye
con SwiftPM y el Info.plist va embebido en el ejecutable, así que para
desarrollo basta con:

```sh
swift build -c release
.build/release/Marcus
```

## Generar Marcus.app y el .dmg

```sh
scripts/build-dmg.sh
```

Deja en `dist/` un `Marcus.app` (binario universal arm64 + x86_64, firmado
ad-hoc) listo para arrastrar a `/Applications`, y un `Marcus-X.Y.Z.dmg` con
el enlace a Applications dentro. La versión se lee del Info.plist.

La firma ad-hoc basta para usar la app en la máquina donde se compiló. En
otro Mac, Gatekeeper la bloqueará al primer intento (clic derecho → Abrir
para autorizarla); distribuir sin fricción requiere Developer ID +
notarización (ver "Pendiente").

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

Con la Fase 2 cerrada, este es el siguiente bloque de trabajo de
distribución; se documentará en detalle cuando toque:

- **Firma**: certificado Developer ID Application y `codesign` con hardened
  runtime. Requiere migrar de Info.plist embebido a bundle real firmado
  (posiblemente con un proyecto Xcode o xcodegen — ver D8).
- **Notarización**: `xcrun notarytool submit` + `xcrun stapler staple`.
- **Actualizaciones**: integración de Sparkle 2 (appcast firmado, clave EdDSA).
- **CI**: pipeline que ejecute build + tests + presupuestos de rendimiento
  en cada push y produzca el artefacto de release en cada tag.
