# DEPLOY — Build de release y distribución

Marcus es una app de escritorio para macOS: aquí "desplegar" significa
producir un `Marcus.app` distribuible. La estrategia de distribución está
decidida en el [ROADMAP](ROADMAP.md) (D8 y D9): **releases de GitHub** con
`.dmg` firmado ad-hoc. Developer ID, notarización y Sparkle quedan
documentados al final por si algún día se crea la cuenta de Apple Developer;
el App Store se evaluará después.

## Estado actual

Hay releases etiquetadas (última: v0.3.0) con `.app` y `.dmg` firmados
ad-hoc. El binario se construye con SwiftPM y el Info.plist va embebido en
el ejecutable, así que para desarrollo basta con:

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

`dist/` está en `.gitignore`; los bundles no se versionan.

### Qué implica la firma ad-hoc para quien descarga

En la máquina donde se compiló, la app abre sin avisos. Descargada de
internet (p. ej. desde un release de GitHub), Gatekeeper la bloqueará la
primera vez por no estar notarizada:

- **macOS 14 o anterior**: clic derecho sobre la app → Abrir → Abrir.
- **macOS 15 (Sequoia) o posterior**: intentar abrirla una vez, luego
  Ajustes del Sistema → Privacidad y seguridad → botón «Abrir de todos
  modos», y autenticarse.

Conviene incluir estas dos líneas en las notas de cada release de GitHub.

## Checklist de release

1. `swift test` en verde.
2. Presupuestos de rendimiento del ROADMAP verificados en release
   (`swift test -c release`; son bloqueantes).
3. Actualizar `CFBundleShortVersionString` e incrementar `CFBundleVersion`
   en [Sources/Marcus/Info.plist](Sources/Marcus/Info.plist).
4. Mover lo hecho de `[Sin publicar]` a la nueva versión en
   [CHANGELOG.md](CHANGELOG.md) con la fecha del día.
5. Commit de release y tag anotado: `git tag -a vX.Y.Z -m "Marcus X.Y.Z"`.
6. Generar el bundle (apartado anterior) y prueba de humo manual: abrir,
   editar, guardar, buscar, cerrar y reabrir (sesión restaurada).
7. Push (`git push && git push --tags`) y release en GitHub con el `.dmg`
   adjunto y las notas de la versión desde el CHANGELOG (más el aviso de
   Gatekeeper del apartado anterior):

   ```sh
   gh release create vX.Y.Z dist/Marcus-X.Y.Z.dmg \
     --title "Marcus X.Y.Z" --notes "…"
   ```

## Pendiente

- **CI**: pipeline (GitHub Actions, runner macOS) que ejecute
  `swift build` + `swift test -c release` — con los presupuestos de
  rendimiento bloqueantes — en cada push, y en cada tag genere el `.dmg`
  y lo adjunte al release de GitHub.

## Si algún día hay cuenta de Apple Developer (proceso documentado, no activo)

Requisito: cuenta de pago de Apple Developer (99 €/año). Con ella, la app
se distribuye sin fricción de Gatekeeper. Pasos, en orden:

1. **Certificado**: en developer.apple.com → Certificates, crear uno de tipo
   «Developer ID Application» e instalarlo en el llavero. Identificar el
   `TEAMID` (Membership).

2. **Firma con hardened runtime** (requisito de la notarización). En
   `build-dmg.sh`, sustituir la firma ad-hoc por:

   ```sh
   codesign --force --options runtime --timestamp \
     --sign "Developer ID Application: NOMBRE (TEAMID)" "$APP"
   ```

   Nota (D8): si la app llegara a necesitar entitlements o recursos más
   complejos, migrar de Info.plist embebido a proyecto Xcode/xcodegen;
   para el bundle actual el script basta.

3. **Notarización** (una vez por release, sobre el `.dmg` ya firmado):

   ```sh
   # Una sola vez: guardar credenciales en el llavero
   # (la contraseña es una "app-specific password" de appleid.apple.com)
   xcrun notarytool store-credentials marcus-notary \
     --apple-id CORREO --team-id TEAMID --password APP_SPECIFIC_PASSWORD

   # En cada release
   xcrun notarytool submit "dist/Marcus-X.Y.Z.dmg" \
     --keychain-profile marcus-notary --wait
   xcrun stapler staple "dist/Marcus-X.Y.Z.dmg"
   ```

   `--wait` espera el veredicto (minutos). Si falla, `xcrun notarytool log
   <submission-id> --keychain-profile marcus-notary` explica el motivo.

4. **Actualizaciones con Sparkle 2** (opcional, tras lo anterior):
   dependencia SwiftPM `sparkle-project/Sparkle`, generar el par de claves
   EdDSA con su herramienta `generate_keys`, añadir `SUFeedURL` (URL del
   `appcast.xml`, p. ej. en GitHub Pages o en los assets del release) y
   `SUPublicEDKey` al Info.plist, y publicar cada release en el appcast
   firmado con `generate_appcast`. Hasta entonces, actualizar es descargar
   el `.dmg` nuevo del release.
