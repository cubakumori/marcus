# Marcus — Roadmap de implementación

> Documento operativo. La visión y el manifiesto viven en
> [my.docs/Plan_de_Implementacion_Marcus.md](my.docs/Plan_de_Implementacion_Marcus.md);
> este archivo registra las decisiones técnicas, los presupuestos de rendimiento
> y el estado de cada fase.

**Marcus** es un editor de Markdown nativo para macOS: extremadamente rápido,
ligero y sin ecosistema. Abre, edita y guarda `.md` de forma excelente. Nada más.

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

## Fase 0 — Esqueleto ✅

- [x] Paquete SwiftPM: `MarcusCore` (lógica pura, testeable) + `Marcus` (app AppKit) + tests
- [x] Info.plist embebido con tipos de documento (`net.daringfireball.markdown`: `.md`, `.markdown`, `.mdown`)
- [x] `swift build` y `swift test` en verde desde línea de comandos

## Fase 1 — Editor ✅ (v0.2.0)

El objetivo de salida: escribir Markdown en Marcus a diario es mejor que en TextEdit/VS Code para esa tarea.

- [x] App de documentos `NSDocument`: nuevo, abrir, guardar, guardar como, revertir, Open Recent
- [x] Editor `NSTextView` sobre TextKit 2, sin sustituciones automáticas (comillas/guiones inteligentes desactivados: corrompen Markdown)
- [x] Resaltado de sintaxis incremental real: cada edición re-escanea solo desde la línea editada y se re-empalma con el escaneo anterior en cuanto el estado del escáner coincide (~4 ms por pulsación en un documento de 10 MB). Cubre encabezados, código en línea y bloques (fences e indentado), negrita/cursiva, enlaces, citas, listas, separadores
- [x] Deshacer/rehacer integrado con el documento (estado "editado", punto de guardado)
- [x] Autoguardado y versiones (`autosavesInPlace`)
- [x] Buscar y reemplazar (find bar nativa, búsqueda incremental)
- [x] Codificaciones: UTF-8 ± BOM, fallback de detección, CRLF preservado
- [x] Atajos y menús estándar completos
- [x] Tests unitarios del escáner (casos límite: fences sin cerrar, CRLF, breaks temáticos vs listas…)
- [x] Cambios externos al archivo: recarga silenciosa si no hay ediciones sin guardar; diálogo (conservar/recargar) si las hay
- [x] Tests de rendimiento automatizados contra los presupuestos (1/10 MB sintéticos; se verifican en release y bloquean si se incumplen)
- [x] Modo claro/oscuro: sigue al sistema + conmutador manual (View → Appearance) persistido
- [x] Tests de propiedad del escáner: 400 ediciones aleatorias donde el re-escaneo incremental debe ser idéntico al escaneo completo, más documento de tortura con invariantes (sustituye al corpus de CommonMark: verifica lo que de verdad prometemos — consistencia — en vez de conformidad de spec que un resaltador no necesita)
- [x] Recuperación de sesión verificada manualmente (ventanas restauradas tras relanzar, ediciones sin guardar intactas)

## Fase 2 — Vista previa y exportación ✅ (v0.3.0)

- [x] Vista previa **nativa** (TextKit + `swift-markdown` como AST): panel dividido conmutable con ⌘⇧P. Con la preview oculta el coste es cero (no se parsea nada)
- [x] Renderizado diferido: debounce de 300 ms y parseo + construcción del `NSAttributedString` fuera del hilo principal; solo mostrar el resultado toca la UI. La edición jamás espera
- [x] Imágenes locales en la preview (resueltas contra la carpeta del documento, reescaladas a un ancho máximo)
- [x] GFM en la preview: tablas (rejilla monoespaciada v1 — TextKit 2 no maqueta tablas nativas), listas de tareas, tachado
- [x] Ajustes (⌘,) en SwiftUI (superficie secundaria — ver D1) con el modo de la preview: panel lateral (por defecto) o ventana completa
- [x] Exportar HTML (plantilla mínima, CSS embebido, autocontenido: imágenes locales como data URIs)
- [x] Exportar PDF / imprimir (vía `WKWebView` bajo demanda, JS desactivado — ver D7)
- [x] Temas del editor: System (sigue la apariencia), Sepia y Midnight — fijos, en Ajustes; los temas no son un ecosistema

## Fase 3 — Navegación y productividad ✅

- [x] Outline del documento (índice de encabezados **en memoria, por documento** — sin base de datos, sin indexación de carpetas; ver principio "sin ecosistema"). Barra lateral conmutable (⌘⇧O) derivada del scan del resaltador: no se re-parsea nada
- [x] Ir a encabezado: clic en el esquema salta al encabezado (caret + scroll + indicador). Navegación por teclado tipo "Open Quickly" queda fuera por ahora; se añadiría como refinamiento si se echa en falta
- [x] Ayudas de escritura: continuar listas al pulsar ⏎ (viñetas, numeradas, tareas; ítem vacío cierra la lista) — opt-in en Ajustes, desactivada por defecto porque cambia el comportamiento de ⏎. Menú Format con ⌘B/⌘I que envuelven/des-envuelven la selección (componen negrita+cursiva), siempre disponibles porque solo actúan al invocarlos
- [x] Contador de palabras/caracteres: barra discreta bajo el editor (View → Show Word Count, persistido; oculta por defecto y sin coste mientras no se muestra). Recuento lingüístico (los marcadores Markdown no cuentan) fuera del hilo principal
- [x] Abrir enlaces `[texto](url)` con ⌘-clic (clic normal edita; ⌘-clic abre — relativos resueltos contra la carpeta del documento)
- [x] Guía integrada (Ayuda → Guía de Marcus): `Guide.en.md`/`Guide.es.md` embebidos en el bundle (fuera de los `.lproj`, que compile-strings.sh regenera), abiertos en solo lectura — sin autosave ni estado sucio. Manual y demo a la vez; documenta atajos, ajustes y los mecanismos del sistema (atajos personalizados, idioma por app)
- [x] La vista previa adopta lo básico del tema del editor (fondo y tintas de la paleta activa vía `PreviewRenderOptions`; la tipografía de lectura sigue siendo suya) para que el panel no desentone con Sepia/Midnight

## Fase 4 — Versatilidad (sin perder el minimalismo)

Objetivo: que Marcus sirva para más situaciones reales sin añadir ecosistema.
Entra en v0.4.0.

- [ ] Texto plano: abrir y guardar `.txt` además de `.md`. **Sin adivinar la
  extensión por contenido**: el tipo sigue al archivo (un `.txt` abierto se
  guarda como `.txt`), los documentos nuevos son `.md` por defecto y el panel
  de guardado permite elegir el formato — el panel ya es la confirmación, no
  hace falta un ajuste aparte
- [ ] «Abrir documentos en pestañas» (Otros ajustes): las aperturas desde
  Finder se agrupan como pestañas de una única ventana (`tabbingMode`
  preferido) en vez de ventanas sueltas. Desactivado, manda el ajuste global
  del sistema, como hasta ahora
- [ ] Copiar como HTML (menú Edición): la selección — o el documento si no
  hay selección — al portapapeles como HTML del exportador, para pegar con
  formato en correo, foros o blogs
- Candidatos (se decidirá cuando toquen): front matter YAML tolerante
  (atenuado como metadatos, no roto como falsa lista/separador); arrastrar
  una imagen al editor inserta el enlace relativo

## Transversal (toda fase)

- [ ] Accesibilidad: VoiceOver operativo, respetar tamaño de texto del sistema
- [x] i18n (ver D14): literales de UI (menús, ajustes, diálogos) en String Catalogs con inglés base + español. Los `.xcstrings` son la fuente editable; `scripts/compile-strings.sh` genera los `.lproj` commiteados porque `swift build` aún no compila catálogos
- [ ] Cero trabajo en el arranque que no sea imprescindible para teclear (se audita con Instruments en cada fase)

## No-objetivos (permanentes)

Sin workspaces obligatorios, sin sincronización propia, sin base de datos, sin
indexación permanente, sin plugins en el arranque, sin Electron ni web views en
la ruta de edición. Los archivos pertenecen al usuario.
