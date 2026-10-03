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
| D11 | Codificación | Lectura: UTF-8 (con o sin BOM), UTF-16/32 por BOM, y detección de codificación **sin pérdida** como fallback — los binarios (bytes NUL) y las conversiones con pérdida se rechazan con un error claro antes que abrir algo que el autoguardado reescribiría dañado. Escritura: siempre UTF-8 sin BOM. Los fines de línea se preservan de verdad: se detecta el estilo dominante (LF/CRLF/CR) al leer, en memoria solo hay `\n`, y se restaura el estilo al guardar (`TextFile`/`LineEnding` en MarcusCore) | "El archivo es la fuente de verdad" |
| D12 | Plugins | **Fuera del roadmap.** Queda como principio (opcionales, aislados, sin coste de arranque) pero no se diseña API hasta que exista demanda real | Evita presión de diseño prematura |
| D13 | Licencia | **AGPL-3.0-or-later** (`LICENSE` en la raíz) | Copyleft fuerte: las mejoras vuelven al proyecto |
| D14 | i18n | **String Catalogs** de Xcode (`Localizable.xcstrings`): inglés como idioma base del código, español como primera localización; sigue el idioma del sistema | Es el mecanismo nativo actual, extrae los literales automáticamente y no añade dependencias ni coste de arranque |
| D15 | Abrir cualquier texto (Fase 6) | Conformidad con `public.plain-text` (rol editor) declarada **una sola vez** en el Info.plist — sin enumerar formatos — más un único ajuste opt-in «Abrir cualquier archivo de texto», desactivado por defecto. El guardado no necesita ajuste: el tipo sigue al archivo, como ya pasa con `.txt`. Los formatos no-Markdown se editan como **texto plano honesto**: sin resaltado, sin preview renderizada, sin exportaciones Markdown. `.md` y `.txt` conservan su comportamiento actual | Edición ocasional de HTML/CSS/JS/.conf/.log… *como texto*, sin fingir ser un editor de código. Los tipos declarados son estáticos: una lista de checkboxes en Ajustes no podría activarlos/desactivarlos en caliente |
| D16 | Front matter YAML (Fase 7) | Detección **puramente posicional**: hay front matter solo si la línea 1 del archivo es exactamente `---`, hasta la primera línea posterior que sea exactamente `---` (el cierre); sin cierre no hay front matter. **Sin parser de YAML, sin validación, sin dependencias nuevas**: el contenido del bloque nunca se interpreta. En el editor el bloque se atenúa con la tinta terciaria y no se escanea como Markdown por dentro; preview, exportaciones, Copiar como HTML y el outline lo omiten | Los generadores estáticos y las apps de notas ponen metadatos ahí; pintarlos como falsa lista/separador/setext los rompe visualmente. Marcus los trata como lo que son — metadatos, no texto — sin convertirse en herramienta de YAML |
| D17 | Sub/superíndices (ayuda de escritura; posterior a v0.7.0) | Comandos en el menú Format —junto a Negrita (⌘B) y Cursiva (⌘I)— que **transliteran la selección a los caracteres Unicode** de sub/superíndice (`2`→`²`, `2`→`₂`): superíndice `⌃⌘=`, subíndice `⌃⌘-` (estilo Pages sin Shift). **Toggle**: si todo lo convertible ya está en esa forma, revierte a ASCII; si no, convierte lo que falte (revertir normaliza a ASCII). **Sin selección**, actúa sobre la palabra del caret (así `H2O`→`H₂O` con el caret dentro). **Límite honesto**: solo convierte lo que Unicode tiene como sub/superíndice — dígitos y los signos `+ - = ( )` completos en ambos sentidos, letras parciales (las mayúsculas casi no tienen subíndice, de ahí que `H`/`O` no bajen); lo no convertible se deja igual. Lógica pura en `MarcusCore` (`ScriptToggle`), reutilizando el patrón de `EmphasisToggle` | Es **ayuda de escritura, NO extensión del dialecto**: el archivo guarda Unicode plano, así que preview, exportaciones y Copiar como HTML no tocan nada y **D6 (dialecto fijo) queda intacto** — no hay sintaxis nueva ni colisión con `~~`. Explícito y sin magia frente a un disparador de tecleo estilo Pandoc (`x^2^`). Portable: se ve igual en GitHub y en cualquier editor |
| D18 | Zoom de texto in-app (posterior a 0.8.0) | Factor global persistido que escala **el editor y la preview** (el contenido, no la barra de recuento ni el outline): `⌘+` aumenta, `⌘-` reduce, `⌘0` vuelve al 100 %. Compone sobre DynamicType — `tamaño = base × escalaSistema × zoom` —, clamp a `[0.5, 3.0]` en rejilla de 0.1 sin deriva. Lógica pura `ZoomStep` en `MarcusCore`; se aplica en vivo por la misma vía que el cambio de tema (el highlighter recalcula sus fuentes, el editor re-resalta y la preview re-renderiza) | Comodidad de lectura/escritura esperada en un editor: instantánea, por-app y persistida. **Complementa** Dynamic Type (accesibilidad del sistema, global y solo al relanzar) sin sustituirlo — es justo el reflow en caliente que aquél dejó fuera, como palanca del usuario. `⌘` es la convención macOS (Safari, Xcode); no colisiona con los sub/super (`⌃⌘`) |

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
- Verificación de UI sin interacción: ganchos por argumento de lanzamiento (`-MarcusDebug… valor`), leídos de UserDefaults. Lanzar siempre con `-ApplePersistenceIgnoreState YES` y `-MarcusDebugNoActivate YES` (una app que se activa se traga lo que el usuario teclea en otra, y el autoguardado lo persiste). La restauración de sesión solo se prueba con un bundle `.app` **con otro `CFBundleIdentifier`** (p. ej. `com.cubakumori.marcus.test`), que aísla preferencias y estado del Marcus real, y `-NSQuitAlwaysKeepsWindows YES`. Preferir los volcados JSON a las capturas de pantalla (`screencapture` exige permiso y capta la pantalla del usuario; `-MarcusDebugSnapshot` no)

| Gancho | Qué hace |
|--------|----------|
| `-MarcusDebugOpenFile /a,/b` · `-MarcusDebugOpenFileDelayed /a` | Abre archivos al arrancar · 2,5 s después (ruta Finder/odoc, pestañas) |
| `-MarcusDebugShowPreview YES` · `-MarcusDebugShowOutline YES` · `-MarcusDebugTogglePreviewAfter N` | Muestra la preview · el esquema · conmuta la preview a los N s |
| `-MarcusDebugShowSettings/ShowAbout/ShowGuide/ShowSaveAs YES` | Abre Ajustes · Acerca de · la guía · Guardar como |
| `-MarcusDebugTypeText "a\nb"` | Teclea por `insertText` a 1 s (`\n` es ⏎): reproduce lo que pasa «al escribir» |
| `-MarcusDebugApplyScript "sub;loc,len;/out.json"` | Aplica sub/superíndice a un rango (len 0: palabra del caret) y vuelca el texto |
| `-MarcusDebugPaste "https://x;loc,len;/out.json"` | Pega el texto sobre el rango por la ruta de ⌘V desde un portapapeles privado (el del usuario no se toca) y vuelca texto, caret y si creó enlace |
| `-MarcusDebugInsertImage "/a.png,/b.png;loc,len;/o.json"` | Pega esos archivos como si vinieran de Finder (portapapeles privado) sobre el rango y vuelca texto, selección, si se trató y si apareció el aviso de guardar |
| `-MarcusDebugCaretAt N` | Coloca el caret en el offset UTF-16 N a 2 s (sync editor→preview) |
| `-MarcusDebugCopyHTML YES` | Copiar como HTML; inspeccionar luego el portapapeles |
| `-MarcusDebugShare "pdf;/o.json"` | Compartir como HTML/PDF/RTF (`html`, `pdf`, `rtf`) a los 2 s; a los 5 s vuelca el archivo ofrecido (ruta, bytes), los servicios propuestos por el sistema y las ventanas visibles ajenas al documento (la hoja) |
| `-MarcusDebugExportPDF /out.pdf` · `-MarcusDebugExportRTF /out.rtf` | Exporta el PDF (en texto plano honesto, la impresión monoespaciada) · el RTF sin panel |
| `-MarcusDebugSaveAfter N` · `-MarcusDebugQuitAfter N` | Guarda el documento frontal a los N s (bytes escritos) · sale limpio por `NSApp.terminate` (guarda estado) |
| `-MarcusDebugDumpDocState /o.json` | A 2 s: nombre, URL, formato, subtítulo, barra de recuento, ortografía, fuente inicial, texto de la preview |
| `-MarcusDebugDumpSyncState /o.json` | A 4 s: scroll y anclas de la preview, `syncedLocation`, caret del editor, longitud del texto |
| `-MarcusDebugDumpA11y /o.json` | A 1,5 s: etiquetas VoiceOver, último anuncio, primer respondedor, orden de paneles, escala Dynamic Type |
| `-MarcusDebugSnapshot /o.png` | A 3 s: PNG de la ventana dibujado por la app + `.json` de geometría del editor y anchos de paneles + `.constraints.txt` |
| `-MarcusDebugDumpLaunchTime /o.json` | ms desde el exec hasta el fin del lanzamiento y hasta el primer idle (presupuesto < 500 ms, medir en release y bundle) |
| `-MarcusDebugTextScale 1.5` | Fuerza el factor de Dynamic Type |
| Ajustes como argumento | Cualquier clave persistida vale como argumento: `-MarcusEditorTheme sepia`, `-MarcusPreviewMode full`, `-MarcusEditorZoom 1.4`, `-MarcusShowWordCount YES`, `-MarcusCheckSpelling NO`, `-MarcusSpellingLanguage es`, `-MarcusOpenInTabs YES`, `-MarcusOpenAnyText YES`, `-AppleLanguages "(en)"` |

## Fase 6 — Marcus abre cualquier texto (publicada en v0.6.0)

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
  menú desactivado. Decidido al cerrar (luego hecho, 2026-10-03): imprimir no-Markdown queda
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
- Re-auditoría 2026-10-02 (tras v0.7.0, D17, D18, ortografía,
  restauración de paneles y la pasada de robustez; release, bundle,
  mismo gancho, mediana de 5 arranques templados): ~185 ms hasta el fin
  del lanzamiento, ~205 ms hasta el primer idle. Primer arranque del
  binario recién firmado: ~750 ms (coste único del sistema, como
  entonces). El presupuesto de <500 ms se cumple con margen; el único
  resaltado al abrir (antes eran dos) compensa de sobra el registro de
  defaults y la ortografía.

## Fase 7 — Front matter YAML tolerante (publicada en v0.6.0; pendiente ronda manual)

Diseño acordado 2026-07-07, registrado como D16: detección puramente
posicional (línea 1 exactamente `---`, hasta el cierre exacto `---`;
sin cierre no hay bloque), sin parser de YAML, sin validación, sin
dependencias nuevas. Aplica donde aplica el tratamiento Markdown
(`.md` y `.txt`, Fase 4); los formatos honestos de la Fase 6 ni se
enteran.

Consecuencias asumidas del diseño posicional:

- Un documento que empieza con una raya `---` exacta y tiene otra más
  abajo cede ese prefijo a los metadatos, sea o no YAML válido — es el
  precio de no validar. Es el mismo trato que dan Jekyll u Obsidian.
- La existencia del bloque depende de dos líneas lejanas entre sí
  (apertura y cierre), así que una edición en un documento cuya línea 1
  es `---` re-escanea el documento entero en vez de re-escanear
  incrementalmente desde la línea editada. Los documentos con front
  matter reales son notas de KBs (el escaneo completo de 1 MB ronda los
  6 ms, dentro del presupuesto de tecleo); un documento enorme que no
  empieza por `---` no paga nada.
- La detección es posicional *sobre el texto que recibe cada
  consumidor*: Copiar como HTML de una selección que empiece por `---`
  también omite ese bloque — coherente con lo que la selección es, un
  documento pequeño.

Trabajo:

- [x] Lógica (MarcusCore, tests primero): clasificación de las líneas
  del bloque en el escáner (`LineKind.frontMatter`, estado entre líneas
  como el de los fences; re-escaneo completo cuando la línea 1 es `---`)
  y helper de recorte (`FrontMatter.block(in:)`) para los consumidores.
  19 tests
- [x] Editor: el bloque entero (delimitadores incluidos) atenuado con la
  tinta terciaria del tema, sin estilos Markdown por dentro; el outline
  lo ignora solo (ninguna línea del bloque es un encabezado)
- [x] Preview, Exportar HTML/PDF, Imprimir, Copiar como HTML y el
  recuento de palabras omiten el bloque (todos los caminos HTML pasan por
  `MarkdownHTMLExporter.body`); las anclas del sync editor→preview
  conservan las líneas del documento completo. 8 tests
- [x] Guía integrada al día (sección nueva de front matter, en/es)
- [ ] Ronda manual de Ernesto: atenuado visual en los tres temas y
  animación del primer despliegue de preview/outline (ahora se crean
  perezosos)

## v0.7.0: Accesibilidad (implementada; sin release propia — sale con v0.8.0)

Decisión (2026-07-07): tras publicar v0.6.0, el siguiente objetivo con
nombre es saldar el transversal de accesibilidad, abierto desde la
Fase 0. Se eleva a release propia en vez de embutirlo a última hora en
v0.6.0 (que ya está hecho y solo espera la ronda manual de la Fase 7):
hacerlo bien exige una ronda real de VoiceOver, que es manual, y
probablemente iterar sobre lo que aparezca. «La experiencia por defecto
debe ser la mejor» tampoco se cumple hoy para quien usa VoiceOver.

Nota (2026-10-02): el CHANGELOG cerró [0.7.0] con fecha 2026-07-12, pero
nunca se creó el tag ni la release en GitHub (la última publicada es
v0.6.0) y el Info.plist pasó directamente a 0.8.0. Decidido: no se
publica 0.7.0 retroactivamente; la accesibilidad sale con v0.8.0 junto a
D17, D18 y las correcciones posteriores. El CHANGELOG lo anota en la
propia entrada.

Alcance:

- [x] VoiceOver: `accessibilityLabel`, roles y orden de foco lógico en
  las vistas propias — celdas del outline (dicen su nivel), barra de
  recuento (frase hablada sin los «·»), el ojo del modo ventana completa
  y el `NSTextView` de solo lectura de la preview (nombrado distinto del
  editor). Anuncios al mostrar/ocultar preview y outline. Orden de foco
  outline → editor → preview; foco inicial en el editor (en la preview
  cuando ocupa la ventana). Gancho `-MarcusDebugDumpA11y`
- [x] Respetar el tamaño de texto del sistema (Dynamic Type) en el
  editor, la UI (barra de recuento, outline) y la preview, vía el factor
  único de `DynamicType`. Gancho `-MarcusDebugTextScale`
- [ ] Verificación: ganchos de accesibilidad hechos y verde en
  automatizado (labels, roles, orden de paneles, anuncios registrados,
  escalado de fuentes de punta a punta). **Pendiente la ronda manual de
  VoiceOver de Ernesto** (lo interactivo no se puede simular)

Ronda manual pendiente (Ernesto):

- VoiceOver de verdad (⌘F5): recorrer los paneles con VO y confirmar que
  el orden y las etiquetas suenan naturales; que la barra de recuento se
  lee como una frase; que los anuncios de preview/outline se oyen al
  conmutar (⌘⇧P / ⌘⇧O) y no molestan de más; que el ojo de ventana
  completa es alcanzable en pantalla completa de macOS.
- Dynamic Type visual: Ajustes del Sistema → Accesibilidad → Pantalla →
  Tamaño de texto, subirlo y **relanzar Marcus** (el tamaño se toma al
  construir las vistas; el reflow en caliente no está y queda como
  posible mejora si molesta). Mirar en los tres temas que el editor, la
  barra de recuento, el outline y la preview crecen sin recortes ni
  solapes.

Nota: la pasada barata de `accessibilityLabel`/rol en las vistas propias
se consideró para v0.6.0 y se pospone aquí, para no partir el trabajo.

## Tras v0.8.0 — próximos pasos acordados (2026-10-02)

Los puntos 1–3 se publicaron en v0.9.0 (2026-10-03).

En este orden, por valor frente a coste y todos dentro del manifiesto:

1. ~~Pegar una URL sobre una selección crea el enlace `[selección](url)`~~
   — hecho (2026-10-03): `LinkPaste` en MarcusCore (19 tests), `paste(_:)`
   del editor cede al sistema cuando no procede; ver el CHANGELOG
2. ~~Menú Compartir nativo (`NSSharingServicePicker`) con el HTML o el PDF
   exportados~~ — hecho (2026-10-03): Archivo → Compartir → como HTML /
   como PDF, archivo temporal con el nombre del documento, hoja anclada
   bajo la barra de título; ver el CHANGELOG
3. ~~Exportar a RTF desde el `NSAttributedString` de la preview~~ — hecho
   (2026-10-03): Archivo → Exportar como RTF… y Compartir como RTF…,
   paleta fija de papel, imágenes como texto alternativo; ver el
   CHANGELOG. Decidido (2026-10-03): RTF ahora y `.docx` después con
   escritor propio — ver «Candidatas»
4. Candidatas de abajo: insertar imágenes e imprimir texto plano, hechas
   (2026-10-03, sin publicar); sigue `.docx` con escritor propio. La
   release automatizada por tag en CI (DEPLOY) queda aplazada por
   decisión de Ernesto (2026-10-03)
5. Notarización en cuanto exista cuenta de Apple Developer (DEPLOY)

## Candidatas para fases futuras

- Exportar a Word (`.docx`) con un **escritor OOXML propio desde el AST**
  de `swift-markdown` (como `MarkdownHTMLExporter`), no desde el
  `NSAttributedString`: medido el 2026-10-03, el escritor `.officeOpenXML`
  de AppKit pierde enlaces, imágenes y el fondo del código (solo conserva
  fuentes, negrita/cursiva/tachado, colores, sangrías y espaciado). Un
  `.docx` es un zip de XML: el escritor propio puede llevar enlaces,
  imágenes incrustadas y estilos de párrafo con nombre (Título 1…), que
  Word entiende mejor que el formato directo. EPUB más adelante. Lo que
  *no* entra: importar `.docx` a Markdown (conversión con pérdida, fuera
  del manifiesto)
- ~~Imprimir documentos no-Markdown como texto plano~~ — hecho
  (2026-10-03): monoespaciado de 10 pt sobre blanco, líneas largas
  partidas, `NSTextView` paginado por AppKit sin WebKit
  (`PlainTextPrinter`); exportaciones y Compartir siguen desactivados en
  esos formatos. Ver el CHANGELOG
- ~~Arrastrar una imagen al editor inserta el enlace relativo~~ — hecho
  (2026-10-03), ampliado a Formato → Insertar imagen… (⌘⇧I, también en el
  clic derecho) y ⌘V de imágenes copiadas en Finder, que no obligan a
  colocar ventanas lado a lado. Decidido: sin documento guardado se pide
  guardar antes (no rutas absolutas); las capturas del portapapeles (sin
  archivo) quedan fuera, porque Marcus tendría que crear archivos. Ver el
  CHANGELOG
- ~~**Sub/superíndices por comando de menú**~~ — comprometida como **D17**
  (posterior a v0.7.0) e implementada: comandos en el menú Format que
  transliteran la selección a los caracteres Unicode de sub/superíndice
  (`⌃⌘=` / `⌃⌘-`), con toggle a ASCII y, sin selección, sobre la palabra
  del caret. Detalles resueltos al comprometerla: atajos estilo Pages sin
  Shift, palabra del caret sin selección, mapa inverso obtenido invirtiendo
  los mapas directos. Ver el CHANGELOG.

## Transversal (toda fase)

- [x] Accesibilidad: VoiceOver operativo, respetar tamaño de texto del sistema — implementado (ver «v0.7.0: Accesibilidad»); queda la ronda manual de VoiceOver de Ernesto
- [x] Seguridad de los datos del usuario: nada que Marcus abra puede acabar reescrito dañado por el autoguardado (D11: binarios y conversiones con pérdida rechazados; fines de línea preservados). Cada fase que toque lectura o escritura lo re-comprueba con `-MarcusDebugSaveAfter`
- [x] CI en verde en cada push (`swift build` + `swift test`, ver DEPLOY.md); los presupuestos de rendimiento en release siguen siendo un paso local del checklist
- [x] Cero trabajo en el arranque que no sea imprescindible para teclear — auditado tras las Fases 2–6 (ver «Auditoría de arranque»); se re-audita en cada fase con `-MarcusDebugDumpLaunchTime` y, si hace falta detalle, xctrace

## No-objetivos (permanentes)

Sin workspaces obligatorios, sin sincronización propia, sin base de datos, sin
indexación permanente, sin plugins en el arranque, sin Electron ni web views en
la ruta de edición. Los archivos pertenecen al usuario.
