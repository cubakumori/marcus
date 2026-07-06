# Marcus — Roadmap de implementación

> Documento operativo. La visión y el manifiesto viven en
> [my.docs/Plan_de_Implementacion_Marcus.md](my.docs/Plan_de_Implementacion_Marcus.md);
> este archivo registra las decisiones técnicas, los presupuestos de rendimiento
> y el estado de cada fase.

**Marcus** es un editor de Markdown nativo para macOS: extremadamente rápido,
ligero y sin ecosistema. Abre, edita y guarda `.md` — y texto plano `.txt` —
de forma excelente. Nada más.

---

## Decisiones técnicas (registro)

Cada decisión es revisable, pero cambiarla exige una razón escrita aquí.

| # | Decisión | Elección | Motivo |
|---|----------|----------|--------|
| D1 | Lenguaje y UI | Swift 6 + AppKit. SwiftUI solo para superficies secundarias (preferencias, about) | El editor exige control fino de rendimiento; AppKit/TextKit lo da hoy |
| D2 | Motor de texto | **TextKit 2** (`NSTextLayoutManager`), nunca tocar `layoutManager` (evita el fallback a TextKit 1) | Layout perezoso por viewport → abrir archivos grandes al instante |
| D3 | Modelo de documento | **`NSDocument`** | Autoguardado, versiones, recuperación de sesión, renombrar/mover, Open Recent y revisión al cerrar, gratis y 100% nativos |
| D4 | Resaltado en el editor | **Escáner propio por líneas** (`MarcusCore`), sin dependencias | Un escáner de líneas es O(n) trivial, incremental por diff de líneas y suficiente para colorear; un AST completo es innecesario en la ruta de tecleo |
| D5 | Parser para vista previa/exportación (Fase 2) | `swift-markdown` (cmark-gfm de Apple) | Maduro y conforme a spec; solo se carga al abrir la preview, nunca en el arranque |
| D6 | Dialecto | **CommonMark + GFM parcial**: tablas, listas de tareas, tachado. Nada más | Fijarlo ahora evita re-trabajo; es lo que el 95% de archivos `.md` reales usa |
| D7 | Web views | Prohibidos en la ruta de edición y en el arranque. **Permitido `WKWebView` bajo demanda solo para exportar PDF/imprimir** (JavaScript desactivado, HTML embebido saneado) | La preview será nativa (TextKit); exportar PDF con calidad tipográfica sin WebKit no compensa el esfuerzo |
| D8 | Empaquetado | SwiftPM con Info.plist embebido (`__info_plist`) en Fase 0–1; proyecto Xcode/xcodegen cuando toque firmar y notarizar | `swift build` + `swift test` funcionan en CI sin Xcode project que mantener |
| D9 | Distribución | **Releases de GitHub** con `.dmg` firmado ad-hoc (el usuario autoriza la app en Gatekeeper la primera vez). Developer ID + notarización + Sparkle: proceso documentado en DEPLOY.md, pospuesto hasta que exista cuenta de Apple Developer. App Store: se evaluará después (el sandbox complica la recuperación de sesión) | Revisado 2026-07: la cuenta (99 €/año) no compensa para apps personales de audiencia mínima. Si la audiencia crece, el proceso ya está documentado |
| D10 | Ventanas | Un documento por ventana + pestañas nativas de macOS | Comportamiento estándar de la plataforma, coste cero |
| D11 | Codificación | Lectura: UTF-8 (con o sin BOM) con detección de fallback; escritura: siempre UTF-8 sin BOM. Los fines de línea del archivo se preservan | "El archivo es la fuente de verdad" |
| D12 | Plugins | **Fuera del roadmap.** Queda como principio (opcionales, aislados, sin coste de arranque) pero no se diseña API hasta que exista demanda real | Evita presión de diseño prematura |
| D13 | Licencia | **AGPL-3.0-or-later** (`LICENSE` en la raíz) | Copyleft fuerte: las mejoras vuelven al proyecto |
| D14 | i18n | **String Catalogs** de Xcode (`Localizable.xcstrings`): inglés como idioma base del código, español como primera localización; sigue el idioma del sistema | Es el mecanismo nativo actual, extrae los literales automáticamente y no añade dependencias ni coste de arranque |

---

## Presupuestos de rendimiento

Son requisitos, no aspiraciones. Se verifican con tests de rendimiento y bloquean release si se incumplen.

| Métrica | Presupuesto |
|---------|-------------|
| Arranque en frío hasta poder teclear | < 500 ms |
| Abrir archivo de 1 MB | < 100 ms |
| Abrir archivo de 10 MB | < 1 s |
| Latencia de tecleo (incl. resaltado) | < 16 ms por pulsación |
| Memoria en reposo con un documento típico abierto | < 100 MB |

---

## Hecho (resumen — el detalle vive en CHANGELOG.md y en el historial de git)

- **Fase 0 — Esqueleto** ✅: paquete SwiftPM (`MarcusCore` + app + tests), Info.plist embebido, `swift build`/`swift test` sin proyecto Xcode
- **Fase 1 — Editor** ✅ (v0.2.0): `NSDocument` completo, TextKit 2, resaltado incremental (~4 ms/pulsación en 10 MB), buscar/reemplazar, codificaciones, cambios externos, apariencia; tests de propiedad y de rendimiento (bloqueantes en release)
- **Fase 2 — Vista previa y exportación** ✅ (v0.3.0): preview nativa (⌘⇧P, coste cero oculta), exportar HTML autocontenido (⌘⇧E), PDF/imprimir vía `WKWebView` bajo demanda (D7), i18n en/es (D14), temas del editor, Ajustes (⌘,)
- **Fase 3 — Navegación y productividad** ✅ (liberada con v0.4.0): outline e ir a encabezado (⌘⇧O, derivado del scan del resaltador), preview temada, ayudas de escritura (⏎ continúa listas — opt-in —, ⌘B/⌘I), recuento de palabras, ⌘-clic abre enlaces, guía integrada bilingüe (⌘⇧H)
- **Fase 4 — Versatilidad** ✅ (v0.4.0): texto plano `.txt` (el tipo sigue al archivo, sin adivinar por contenido; el panel de guardado elige el formato), «Abrir documentos en pestañas» opt-in (`tabbingMode` preferido), Copiar como HTML (⌥⌘C, fragmento del exportador + Markdown como respaldo)
- **Fase 5 — Preview conectada** ✅ (v0.5.0): indicador del modo ventana completa (subtítulo de ventana + icono discreto en el contenido, necesario en pantalla completa) y sync editor → preview por anclas de encabezado (el renderizador emite línea fuente → posición renderizada; solo desplaza al cambiar de sección)

Notas operativas:

- i18n: los `.xcstrings` son la fuente editable; tras cambiar cadenas, ejecutar `scripts/compile-strings.sh` y commitear los `.lproj` generados (`swift build` aún no compila catálogos). La guía (`Guide.*.md`) vive fuera de los `.lproj` a propósito
- El Info.plist va incrustado por flag del linker y SwiftPM no lo rastrea: tras editarlo, forzar un re-enlace (p. ej. borrar el binario de `.build`)

## Próxima fase — sin definir

Candidatas (se decidirá cuando toquen):

- Front matter YAML tolerante (atenuado como metadatos, no roto como
  falsa lista/separador)
- Arrastrar una imagen al editor inserta el enlace relativo
- Auditoría de arranque con Instruments (transversal pendiente desde la
  Fase 2; el camino de arranque ha crecido: outline, sync, indicador)

## Transversal (toda fase)

- [ ] Accesibilidad: VoiceOver operativo, respetar tamaño de texto del sistema
- [ ] Cero trabajo en el arranque que no sea imprescindible para teclear (se audita con Instruments en cada fase; pendiente la auditoría tras las Fases 2–4)

## No-objetivos (permanentes)

Sin workspaces obligatorios, sin sincronización propia, sin base de datos, sin
indexación permanente, sin plugins en el arranque, sin Electron ni web views en
la ruta de edición. Los archivos pertenecen al usuario.
