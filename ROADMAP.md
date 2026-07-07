# Marcus — Roadmap de implementación

> Documento operativo: registra las decisiones técnicas, los presupuestos
> de rendimiento y el trabajo por delante. Lo ya hecho vive en
> [CHANGELOG.md](CHANGELOG.md) y en el historial de git.

**Marcus** es un editor nativo para macOS — una herramienta primaria para
texto, optimizada para Markdown (D15) —: extremadamente rápido, ligero y sin
ecosistema. Abre, edita y guarda `.md` y `.txt` de forma excelente, y
(opt-in) cualquier otro formato de texto como texto plano honesto. Nada más.

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
| D15 | Abrir cualquier texto (Fase 6) | Conformidad con `public.plain-text` (rol editor) declarada **una sola vez** en el Info.plist — sin enumerar formatos — más un único ajuste opt-in «Abrir cualquier archivo de texto», desactivado por defecto. El guardado no necesita ajuste: el tipo sigue al archivo, como ya pasa con `.txt`. Los formatos no-Markdown se editan como **texto plano honesto**: sin resaltado, sin preview renderizada, sin exportaciones Markdown. `.md` y `.txt` conservan su comportamiento actual | Edición ocasional de HTML/CSS/JS/.conf/.log… *como texto*, sin fingir ser un editor de código. Los tipos declarados son estáticos: una lista de checkboxes en Ajustes no podría activarlos/desactivarlos en caliente |

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

## Notas operativas

- i18n: los `.xcstrings` son la fuente editable; tras cambiar cadenas, ejecutar `scripts/compile-strings.sh` y commitear los `.lproj` generados (`swift build` aún no compila catálogos). La guía (`Guide.*.md`) vive fuera de los `.lproj` a propósito
- El Info.plist va incrustado por flag del linker y SwiftPM no lo rastrea: tras editarlo, forzar un re-enlace (p. ej. borrar el binario de `.build`)

## Fase 6 — Marcus abre cualquier texto (implementada; pendiente ronda manual y release)

Visión (acordada 2026-07-07, registrada como D15): herramienta simple y
rápida para editar *como texto* archivos de otros formatos (HTML, CSS,
JS, PHP, .conf, .log…), sin pretender competir con editores de código —
edición ocasional, no permanente.

Nota de alcance: «no-Markdown» significa aquí *los formatos nuevos*.
`.txt` conserva íntegro su tratamiento de la Fase 4 (resaltado, preview,
exportación): es el formato hermano de Markdown, mucha gente escribe
Markdown en `.txt`, y quitárselo sería una regresión de algo publicado.
El indicador de formato, en cambio, sí lo cubre: un `.txt` se anuncia
como texto plano porque *es* texto plano.

- [x] Lógica de clasificación de formato (`DocumentFormat` en
  MarcusCore, tests primero): Markdown (`md`/`markdown`/`mdown`, y todo
  documento nuevo sin archivo), texto plano (`txt`/`text`) u otro (por
  extensión, nunca por contenido). El nombre visible se resuelve en la
  capa de app: `UTType.localizedDescription` del sistema (ya localizado)
  con la extensión en mayúsculas como último recurso
- [x] Indicador de formato: en la barra de recuento cuando está visible
  («Markdown · Palabras: … · Caracteres: …») y, para documentos
  no-Markdown (incluido `.txt`), como subtítulo de ventana — mecanismo
  de la Fase 5; el subtítulo «Vista previa» del modo ventana completa
  manda mientras la preview está visible. Sigue a «Guardar como»
  (el tipo sigue al archivo)
- [x] Texto plano honesto para los formatos nuevos: resaltado apagado;
  Exportar HTML/PDF, Copiar como HTML e Imprimir desactivados en el
  menú; ⌘B/⌘I y continuación de listas inertes; outline vacío y su
  menú desactivado. Decidido al cerrar: imprimir no-Markdown queda
  desactivado; «imprimir como texto plano» pasa a candidata
- [x] Preview (⌘⇧P) para los formatos nuevos: mensaje honesto en vez de
  render — «Este formato (X) no admite vista previa. Marcus es una
  herramienta primaria para texto, optimizada para Markdown»
- [x] Ajuste opt-in «Abrir cualquier archivo de texto» (Ajustes → Otros
  ajustes, desactivado por defecto): con él activo, el panel de abrir
  admite cualquier archivo y los tipos no declarados se resuelven como
  `public.plain-text` vía subclase de `NSDocumentController` (si el
  contenido no se decodifica como texto, el error de lectura de siempre
  es la respuesta honesta). Desactivado, todo sigue como hoy — los
  tipos que ya conforman `public.plain-text` (código fuente, logs)
  siempre abrieron por conformidad. Nota: abrir desde Finder solo
  alcanza a los tipos que el sistema sabe que son texto plano; el
  resto entra por File → Open (limitación asumida en D15: los tipos
  declarados son estáticos)
- [x] Al cerrar la fase: ajustar el manifiesto del README y la cabecera
  de este ROADMAP («herramienta primaria para texto, optimizada para
  Markdown»), guía integrada al día (nuevo ajuste y comportamiento)

## Auditoría de arranque (2026-07-07, tras las Fases 2–6)

Método: xctrace (plantilla App Launch) sobre build release + gancho
`-MarcusDebugDumpLaunchTime` (milisegundos desde el exec del proceso,
sin profiler). Máquina: MacBook Air M4, macOS 26.5.

Números (release, sin instrumentar):

| Escenario | Hasta fin del lanzamiento | Hasta primer idle (listo para teclear) |
|-----------|--------------------------|----------------------------------------|
| Arranque templado (mediana de 6) | ~215 ms | ~250 ms |
| Primer arranque de un binario recién construido | ~815 ms | ~870 ms |

- El arranque templado cumple el presupuesto de <500 ms con margen.
- El primer arranque de un binario nuevo lo excede, pero es un coste
  único por binario que pone el sistema (validación de firma, cachés de
  dyld frías), no trabajo nuestro; el usuario lo ve una sola vez tras
  instalar o actualizar. Queda pendiente medir el arranque tras un
  reinicio (`purge` exige sudo): un comando con el gancho de arriba.
- Desglose del CPU del hilo principal durante el lanzamiento
  (instrumentado): el trabajo propio son ~40 ms de la primera carga del
  catálogo de cadenas al construir el menú (coste único e inevitable si
  la UI va localizada) y ~43 ms de creación de ventana + editor
  (imprescindible para teclear). El resto es maquinaria de AppKit
  (apertura del documento sin título, ordenación de ventana y tabbing,
  Quick Look opener, Open Recent) que no controlamos.
- Hallazgo corregido: la preview y el outline construían sus vistas al
  abrir la ventana pese a nacer colapsados; ahora se construyen la
  primera vez que se muestran. Sin efecto medible en el reloj (~210 ms
  igual), pero el camino de arranque queda sin trabajo prescindible.
- Conclusión: no hay nada más recortable sin quitar funcionalidad; el
  camino que creció en las Fases 2–6 (outline, sync, indicadores, KVO,
  controlador de documentos propio) o es perezoso o cuesta
  microsegundos en el lanzamiento.

## Candidatas para fases futuras

- Imprimir documentos no-Markdown como texto plano (en la Fase 6 quedó
  desactivado junto a las exportaciones)
- Front matter YAML tolerante (atenuado como metadatos, no roto como
  falsa lista/separador)
- Arrastrar una imagen al editor inserta el enlace relativo

## Transversal (toda fase)

- [ ] Accesibilidad: VoiceOver operativo, respetar tamaño de texto del sistema
- [x] Cero trabajo en el arranque que no sea imprescindible para teclear — auditado tras las Fases 2–6 (ver «Auditoría de arranque»); se re-audita en cada fase con `-MarcusDebugDumpLaunchTime` y, si hace falta detalle, xctrace

## No-objetivos (permanentes)

Sin workspaces obligatorios, sin sincronización propia, sin base de datos, sin
indexación permanente, sin plugins en el arranque, sin Electron ni web views en
la ruta de edición. Los archivos pertenecen al usuario.
