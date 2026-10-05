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
| `-MarcusDebugShowGuideSection tables` | Abre la guía en esa sección (`markdown`, `tables`, `images`, `shortcuts`, `export`) con el encabezado arriba, como el menú Ayuda; comprobar `editorCaret` y `clipOriginY` con DumpSyncState |
| `-MarcusDebugTypeText "a\nb"` | Teclea por `insertText` a 1 s (`\n` es ⏎): reproduce lo que pasa «al escribir» |
| `-MarcusDebugWrap "*;loc,len;/o.json"` · `"…;dead"` · `"41+option 49;loc,len;/o.json;keys"` | Selecciona el rango y teclea esa tecla como el teclado (vuelca texto, selección y `handled` = envolvió) · con `;dead`, las llamadas de tecla muerta hechas a mano (texto marcado y luego el carácter) · con `;keys`, el primer campo son códigos de tecla (`41+option` = Opción+Ñ, `49` = espacio, `33` = acento grave en el teclado español) convertidos en eventos reales que pasan por el contexto de entrada, teclas muertas de la distribución actual incluidas; deja además `/o.json.trace.txt` con las llamadas a `setMarkedText`/`insertText` recibidas. El ajuste se apaga con `-MarcusWrapSelection NO`. OJO: `[` no puede ir como argumento (UserDefaults interpreta los valores que empiezan por `[`, `(` o `{` como plist y el gancho no recibe nada); el corchete lo cubren los tests. Verificado 2026-10-05: Opción+Ñ+espacio y acento grave+espacio envuelven; el gesto repetido da `~~x~~`; la secuencia Opción+Ñ+Ñ+espacio pierde la segunda virgulilla en la simulación pero **con el teclado real funciona** (ronda de Ernesto, 2026-10-05): límite del modo `keys`, no de la app |
| `-MarcusDebugApplyScript "sub;loc,len;/out.json"` | Aplica sub/superíndice a un rango (len 0: palabra del caret) y vuelca el texto |
| `-MarcusDebugPaste "https://x;loc,len;/out.json"` | Pega el texto sobre el rango por la ruta de ⌘V desde un portapapeles privado (el del usuario no se toca) y vuelca texto, caret y si creó enlace |
| `-MarcusDebugInsertImage "/a.png,/b.png;loc,len;/o.json"` | Pega esos archivos como si vinieran de Finder (portapapeles privado) sobre el rango y vuelca texto, selección, si se trató y si apareció el aviso de guardar |
| `-MarcusDebugFormatTable "offset;/o.json"` · `-MarcusDebugInsertTable "offset;filas;columnas;/o.json"` · `-MarcusDebugTableTab "offset;forward\|backward;/o.json"` · `-MarcusDebugShowInsertTable YES` | Formatea la tabla bajo el offset · inserta una tabla vacía sin la hoja · ⇥/⇧⇥ entre celdas (vuelcan texto, selección y `handled`) · abre la hoja de Insertar tabla |
| `-MarcusDebugServiceText "texto;/o.json"` · `-MarcusDebugServiceOpen "/a.md,/b.txt;/o.json"` | Llaman al proveedor de Servicios con un portapapeles privado como haría el sistema (vuelcan el documento nuevo · los documentos abiertos). ACTIVAN la app. Que el sistema ve los servicios se comprueba sin lanzar nada: `lsregister -f dist/Marcus.app` + `pbs -update` + `pbs -dump` |
| `-MarcusDebugShowMovePrompt YES` · `-MarcusSkipMoveToApplications YES` | Fuerza el aviso «Mover a Aplicaciones» · lo silencia (también lo silencia `-MarcusDebugNoActivate`); es modal: cualquier lanzamiento del bundle fuera de /Applications sin uno de los dos se queda detrás del aviso |
| `-MarcusDebugCaretAt N` | Coloca el caret en el offset UTF-16 N a 2 s (sync editor→preview) |
| `-MarcusDebugCopyHTML YES` | Copiar como HTML; inspeccionar luego el portapapeles |
| `-MarcusDebugShare "pdf;/o.json"` | Compartir como HTML/PDF/RTF/Word (`html`, `pdf`, `rtf`, `docx`) a los 2 s; a los 5 s vuelca el archivo ofrecido (ruta, bytes), los servicios propuestos por el sistema y las ventanas visibles ajenas al documento (la hoja) |
| `-MarcusDebugExportPDF /out.pdf` · `-MarcusDebugExportRTF /out.rtf` · `-MarcusDebugExportDocx /out.docx` | Exporta el PDF (en texto plano honesto, la impresión monoespaciada) · el RTF · el Word sin panel. El `.docx` se mira sin Word con `qlmanage -t -s 1400 -o carpeta out.docx` (Vista rápida) y `unzip -t` |
| `-MarcusDebugSaveAfter N` · `-MarcusDebugQuitAfter N` | Guarda el documento frontal a los N s (bytes escritos) · sale limpio por `NSApp.terminate` (guarda estado) |
| `-MarcusDebugDumpDocState /o.json` | A 2 s: nombre, URL, formato, subtítulo, barra de recuento, ortografía, fuente inicial, texto de la preview |
| `-MarcusDebugDumpSyncState /o.json` | A 4 s: scroll y anclas de la preview, `syncedLocation`, caret del editor, longitud del texto |
| `-MarcusDebugDumpA11y /o.json` | A 1,5 s: etiquetas VoiceOver, último anuncio, primer respondedor, orden de paneles, escala Dynamic Type |
| `-MarcusDebugSnapshot /o.png` | A 3 s: PNG de la ventana dibujado por la app + `.json` de geometría del editor y anchos de paneles + `.constraints.txt` |
| `-MarcusDebugDumpLaunchTime /o.json` | ms desde el exec hasta el fin del lanzamiento y hasta el primer idle (presupuesto < 500 ms, medir en release y bundle) |
| `-MarcusDebugTextScale 1.5` | Fuerza el factor de Dynamic Type |
| Ajustes como argumento | Cualquier clave persistida vale como argumento: `-MarcusEditorTheme sepia`, `-MarcusPreviewMode full`, `-MarcusEditorZoom 1.4`, `-MarcusShowWordCount YES`, `-MarcusCheckSpelling NO`, `-MarcusSpellingLanguage es`, `-MarcusOpenInTabs YES`, `-MarcusOpenAnyText YES`, `-MarcusTableTab NO`, `-MarcusWrapSelection NO`, `-MarcusSuppressMoveToApplications YES`, `-AppleLanguages "(en)"` |

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

## Estado tras v0.12.0 (actualizado 2026-10-05)

Los pasos acordados tras v0.8.0 (pegar URL como enlace, Compartir, RTF) y
las candidatas hechas después están publicados: v0.9.0 (enlace, Compartir,
RTF), v0.10.0 (insertar imágenes, imprimir texto plano, Word), v0.11.0
(tablas, Servicios, mover a Aplicaciones), v0.12.0 (menú Ayuda por
secciones, envolver la selección, tachado y cursiva en el editor; la
primera solo con tag). El detalle vive en el CHANGELOG; aquí solo lo que
queda por delante.

- Modo concentración descartada el 2026-10-05 tras probarla (ver
  «Candidatas»)
- Atajos y AppleScript hechos el 2026-10-05 (sin publicar). Las acciones
  de Atajos no pueden ejecutarse con la firma ad hoc (ver «Candidatas»,
  decisiones heredadas): quedan a la espera de la cuenta de
  desarrollador; AppleScript sí es verificable
- Aviso «Descargando de iCloud…» hecho el 2026-10-05 (sin publicar;
  ronda manual de Ernesto pendiente)
- Siguiente: Writing Tools y más idiomas, en el orden que decida
  Ernesto. Quick Look queda
  pospuesta hasta decidir la firma (ver «Candidatas»)
- Release automatizada por tag en CI: aplazada por Ernesto (2026-10-03).
  Desde 2026-10-04 las versiones nuevas llevan solo tag en GitHub, sin
  release ni `.dmg` (ver «Presentación» y DEPLOY)
- Notarización y App Store en cuanto exista la cuenta de Apple Developer
  (DEPLOY): es la 1.0, ver «Presentación»

## Candidatas para fases futuras

- **Sandbox para la Mac App Store con security-scoped bookmarks**
  (anotada 2026-10-03, requisito para vender en la App Store; D9). En
  sandbox, Marcus solo puede leer el archivo que el usuario abrió, no los
  de al lado: se romperían las imágenes relativas en la vista previa, en
  el HTML/PDF exportados y en el RTF, el ⌘-clic en enlaces relativos y,
  en parte, «Abrir cualquier archivo de texto». Solución (la de iA Writer
  y similares): la primera vez que un documento referencia archivos de su
  carpeta, Marcus pide acceso a esa carpeta con un `NSOpenPanel`
  explicado («Permitir que Marcus muestre las imágenes de esta carpeta»),
  guarda un *security-scoped bookmark* y lo reutiliza en los siguientes
  arranques, sin volver a preguntar. Antes de pagar la cuenta de
  desarrollador: una prueba corta que construya Marcus con el
  entitlement de sandbox y liste qué se rompe (restauración de sesión,
  recarga por cambio externo, Compartir, impresión…), para conocer el
  coste real
- **Vista rápida (Quick Look)** (anotada 2026-10-03, idea tomada de
  MarkEdit): espacio en Finder sobre un `.md` lo muestra renderizado.
  Extensión de Quick Look nativa que reutiliza `MarkdownPreviewRenderer`;
  no toca el arranque de la app. **Pospuesta (2026-10-04)** detrás de
  envolver la selección y modo concentración, y hasta que se decida la
  firma Developer ID: no es seguro que entre; se retomará solo si hay
  demanda o necesidad. Motivo: no choca con el manifiesto (es integración
  con el sistema, como Servicios), pero es la primera pieza que viviría
  fuera del ejecutable y el primer motivo real para complicar D8, por una
  función que beneficia más a quien lee que a quien escribe (la preview
  está a un ⌘⇧P). Alcance ya decidido para cuando se retome, tras
  analizarlo el 2026-10-04:
  - *Empaquetado*: `executableTarget` `MarcusQuickLook` en SwiftPM,
    enlazado con `-e _NSExtensionMain` y `-application_extension`
    (`_NSExtensionMain` lo exporta Foundation), con `Info.plist` propio
    (`NSExtensionPointIdentifier com.apple.quicklook.preview`,
    `QLSupportedContentTypes`) y `.entitlements` con sandbox (macOS lo
    exige a todo appex; la firma ad-hoc lo admite). `build-dmg.sh` arma
    `Contents/PlugIns/MarcusQuickLook.appex` (binario, plist, bundle de
    recursos de MarcusPreview, que `Bundle.module` busca dentro del appex)
    y firma el appex antes que la app. D8 intacto; CI sigue siendo `swift
    build` + `swift test`. Comprobar primero, en una prueba corta, que el
    punto de entrada funciona desde SwiftPM; si no, xcodegen solo para el
    appex. Para la App Store el sandbox obligará a xcodegen de todos
    modos: es el momento natural
  - *Render*: vista nativa (`QLPreviewingController` con un `NSTextView`
    de solo lectura y el `NSAttributedString` del renderer; sin WebKit,
    D7), front matter omitido (D16), **apariencia del sistema** (paleta
    semántica y fondo de texto del sistema, no el papel fijo del RTF: la
    Vista rápida es una ventana viva del sistema y en modo oscuro va
    oscura), Dynamic Type sí, zoom de la app no. Imágenes relativas:
    intentarlas con la carpeta del documento como base; el sandbox de la
    extensión solo garantiza el archivo previsualizado, así que medirlo y,
    si las bloquea, mostrarlas como texto alternativo (`imagesAsText`) y
    documentarlo como límite honesto
  - *Formatos*: solo `net.daringfireball.markdown` (`.md`, `.markdown`,
    `.mdown`). Sin `public.plain-text`: secuestraría la Vista rápida de
    todos los `.txt`, `.log`, `.csv` y archivos de código (D15)
  - *Miniaturas en Finder*: fuera (segundo appex `com.apple.quicklook.thumbnail`
    que se ejecuta por cada `.md` visible; el sistema ya pinta el texto)
  - *Convivencia*: macOS elige entre varias extensiones del mismo tipo sin
    regla documentada; el usuario desactiva la que sobre en Ajustes del
    Sistema → General → Ajustes de inicio de sesión y extensiones → Vista
    rápida. En este Mac (2026-10-04) solo el generador de texto del sistema
    cubre `.md`; la extensión de Bear es para sus notas de Spotlight
  - *Verificación*: lógica pura en MarcusPreview (leer con `TextFile` y
    renderizar) con tests; `scripts/verify-quicklook.sh`: `lsregister -f`
    + `pluginkit -m -v -i …quicklook` (el sistema ve la extensión y su
    tipo) + `qlmanage -p doc.md` (ABRE la ventana de Vista rápida: solo
    con Ernesto ausente); `qlmanage -t` no la ejercita (miniaturas)
  - *Fuera*: texto plano, botón «Abrir en Marcus» (el panel ya ofrece
    «Abrir con»), buscar en el panel, resaltado de sintaxis, leer los
    ajustes de la app desde la extensión (exigiría App Group y equipo)
  - *Costes medidos o esperados*: cero en el arranque de Marcus (otro
    proceso); la primera pulsación de espacio arranca la extensión (~un
    cuarto de segundo, luego el sistema la mantiene viva), frente al
    generador del sistema, instantáneo; el renderer y swift-markdown se
    compilan dos veces (uno o dos MB más de `.app`); dos superficies que
    mantener por cada cambio del renderer
- **Herramientas de escritura del sistema** (anotada 2026-10-03, de
  MarkEdit): comprobar que Apple Intelligence (Writing Tools) y las
  predicciones en línea funcionan en el editor y no estropean el Markdown;
  AppKit las da casi gratis en un `NSTextView`
- **Homebrew** (`brew install --cask marcus`, anotada 2026-10-03, de
  MarkEdit): desde el 2026-09-01 Homebrew solo admite casks que pasan
  Gatekeeper, así que exige firma Developer ID y notarización — depende de
  la cuenta de Apple Developer, como la App Store
- **Modo concentración** (anotada 2026-10-03; ajuste en Ajustes, decidido
  por Ernesto): atenúa todo salvo el párrafo del caret, como iA Writer.
  Solo visual (atributos temporales), opcional, apagado por defecto
- **Modo concentración: descartada** (2026-10-05). Se implementó
  completa (ajuste + ⌘D, bloque por clases de línea del escáner,
  atributos de renderizado de TextKit 2, gancho y 20 tests), Ernesto la
  probó con el bundle y la rechazó: no le gusta la función. El commit
  vive en la rama local `concentracion-descartada` (no empujada); no
  retomarla salvo petición expresa. Lo aprendido, por si vuelve: (1)
  cambiar los atributos de renderizado NO repinta lo ya maquetado —
  en la ronda solo se atenuó lo que aún no había pasado por el layout,
  y el gancho no lo vio porque el volcado y la instantánea llegan tras
  el primer layout; haría falta invalidar el layout del rango visible
  (`invalidateLayout(for:)`) tras cada cambio; (2) un color dinámico con
  alfa deja de ser dinámico: resolver la tinta por apariencia al
  aplicarla; (3) `enumerateRenderingAttributes(from:)` no sirve para
  sondear un offset suelto (devuelve el tramo siguiente); (4) aplicar
  dos tramos sobre 10 MB cuesta 0,2 ms, el coste no era el problema
- **Más idiomas** (anotada 2026-10-03): francés, alemán, portugués e
  italiano, por mercado de la App Store. 108 cadenas en los catálogos más
  la guía (~1.500 palabras). Modelo bajo demanda: plantilla de issue
  «Pedir / aportar un idioma» y traducción por pull request del
  `.xcstrings` y de un `Guide.xx.md` (cubierta por el CLA); el idioma
  entra cuando hay traducción revisada
- Fuera, a propósito: extensiones con JavaScript/CSS al estilo MarkEdit
  (chocan con D7 y D12)
- Decisiones tomadas en candidatas ya hechas (el qué y el cómo, en el
  CHANGELOG; aquí solo lo que condiciona el futuro):
  - Word (2026-10-04): escritor OOXML propio desde el AST. El escritor
    `.officeOpenXML` de AppKit queda descartado para siempre: pierde
    enlaces, imágenes y el fondo del código (medido 2026-10-03). Estilos
    propios «Code»/«Inline Code» en inglés, Helvetica Neue/Menlo como el
    RTF. Fuera, a propósito: importar `.docx`, notas al pie, índice
    automático, cabeceras y pies, casillas interactivas, resaltado de
    sintaxis y plantillas `.dotx` (posible si se pide). EPUB más adelante
  - Tablas (2026-10-04): sin «sobrescribir» tablas ni añadir/quitar
    columnas por menú — Markdown se edita como texto
  - Servicios (2026-10-04): títulos localizados en
    `Resources/*.lproj/ServicesMenu.strings`, copiados por `build-dmg.sh`
    (macOS los busca en el `.app`, no en los bundles de SwiftPM). La
    oferta de moverse a Aplicaciones nació por precaución de Ernesto: los
    servicios siguen a la copia registrada
  - Imágenes (2026-10-03): sin documento guardado se pide guardar antes
    (nunca rutas absolutas); las capturas del portapapeles sin archivo
    quedan fuera, porque Marcus tendría que crear archivos
  - Imprimir no-Markdown (2026-10-03): texto monoespaciado paginado por
    AppKit sin WebKit; exportaciones y Compartir siguen desactivados en
    esos formatos
  - Sub/superíndices: comprometida como D17
  - Envolver la selección (2026-10-04): sin comillas ni paréntesis (no son
    sintaxis), sin des-envolver al teclear (eso es ⌘B/⌘I); las teclas
    muertas del teclado español se cubren en `setMarkedText`
  - Atajos y AppleScript (2026-10-05): las acciones trabajan con
    archivos, nunca con «lo que hay abierto»; los metadatos de App
    Intents los produce `build-dmg.sh` (flags `-emit-const-values` +
    `-const-gather-protocols-file` y `appintentsmetadataprocessor`
    sobre los `.swiftconstvalues` de arm64), así que las acciones solo
    existen en el bundle, no en el ejecutable suelto; los parámetros de
    archivo usan `supportedTypeIdentifiers` (el inicializador tipado
    exige macOS 15); las cadenas van en el `Localizable.strings` del
    propio `.app` (`Resources/Localizable.xcstrings`), con los resúmenes
    en la forma `${parámetro}`. AppleScript: solo Suite estándar +
    `text`; el diccionario completo de texto (párrafos, palabras,
    selección) queda fuera salvo petición. Sin App Shortcuts (frases de
    Siri) ni entidades de documento en Spotlight, por ahora. **Las
    acciones no se ejecutan con firma ad hoc**: `linkd` exige un bundle
    validado con identificador de equipo («requiresValidatedBundle»,
    2026-10-05); solo se podrán probar de verdad con la firma de la
    cuenta de desarrollador. AppleScript no tiene ese límite
  - Archivos en la nube (2026-10-05): la detección es la marca
    `SF_DATALESS` del sistema (vale para cualquier File Provider), la
    descarga se fuerza leyendo un byte en segundo plano (bloquea hasta
    que el proveedor materializa), y el texto nombra iCloud solo si
    `isUbiquitousItem`

## Presentación (anotada 2026-10-04)

Cómo contar Marcus hacia fuera, decidido con Ernesto tras la 0.11.0. Los
textos listos para cada canal viven en sus notas privadas; aquí, las
decisiones y los requisitos previos.

- **Postura, no lista de funciones.** La categoría está llena; Marcus se
  presenta por lo que no hace tanto como por lo que hace. Frase
  propuesta: «Markdown nativo, instantáneo y honesto con tus archivos»
  (EN: «Native Markdown. Instant. Honest with your files.»). Tres
  pilares: **Rápido** (nada corre en el arranque que no sirva para
  teclear) · **Tus archivos** (sin biblioteca, bóveda, base de datos,
  cuenta ni sincronización; el archivo no se reescribe) · **Del Mac**
  (todo nativo: autoguardado, versiones, pestañas, Servicios, Compartir,
  VoiceOver, Dynamic Type). Una sección «Lo que Marcus no hace» va antes
  que las funciones en todos los canales
- **Dónde.** Web propia de Ernesto con dominio para sus apps (la página
  de Marcus, soporte y privacidad; App Store Connect exige las dos URL);
  GitHub Pages no hace falta y el README enlaza a la web. Ficha de la
  Mac App Store en español e inglés (etiqueta de privacidad «No se
  recopilan datos», categoría Productividad). Un «Show HN» en Hacker
  News (app nativa y libre: encaja), r/macapps, Mastodon y Bluesky, y
  correos personales a medios pequeños de apps nativas. Product Hunt
  solo si hay un día entero para atenderlo
- **Modelo y precio (decidido por Ernesto, 2026-10-04): un único precio
  en todas partes y un solo canal de binarios, la Mac App Store.** El
  código sigue libre (AGPL) en GitHub, **solo con tags** (sin releases ni
  `.dmg`; las notas de cada versión viven en el CHANGELOG) e
  instrucciones para compilarlo («gratis si te lo compilas»); el README
  enlaza a la compra en la App Store. Los releases ya publicados (0.8.0
  a 0.11.0, con `.dmg`) se retiran cuando salga la primera versión de la
  App Store, no antes: hasta entonces son la única forma de instalarla.
  Precio: 4,99 $ de salida durante tres meses y después 9,99 $ (decidido
  2026-10-04; App Store Connect permite programar el cambio de precio;
  anunciarlo en la web como precio de lanzamiento con fecha).
  Descartado el modelo
  «gratis en GitHub + de pago en la App Store» (Maccy) por la asimetría
  de precios, y la venta directa con licencias (Paddle, Sparkle) por las
  piezas móviles que añade. Consecuencias: sin Homebrew (exige binario
  descargable; se puede añadir después), DEPLOY pasa de «adjuntar el
  .dmg» a «subir a App Store Connect», `build-dmg.sh` queda para las
  rondas manuales. Con el 15 % del programa para pequeños
  desarrolladores, unas 28 ventas al año cubren la cuenta a 4,99 $ (14 a
  9,99 $). Subir no molesta a quien ya compró, bajar sí; en este tramo
  las ventas de una app de nicho dependen de que la encuentren, no de
  cinco euros
- **Qué es la 1.0** (decidido 2026-10-04): la primera versión publicada
  en la Mac App Store. Ernesto considera a Marcus completo y optimizado
  en lo funcional; la 1.0 no espera a ninguna candidata, solo al paso de
  Apple: cuenta de desarrollador, sandbox con security-scoped bookmarks,
  ronda manual bajo sandbox (restauración de sesión, recarga externa,
  Compartir, impresión, imágenes relativas), revisión aprobada y la
  documentación (README, DEPLOY, guía) ajustada al modelo. Las candidatas
  que entren antes (envolver la selección, modo concentración) van en
  0.x; las que lleguen después, en 1.x
- **Requisitos previos a cualquier campaña**, en orden: cuenta de Apple
  Developer; sandbox + security-scoped bookmarks («Candidatas»); web con
  soporte y privacidad; seis capturas (una por mensaje, 2880 × 1800) y un
  vídeo de diez segundos. El arranque real ya está medido (2026-10-04,
  app instalada en el Mac de Ernesto, `-MarcusDebugDumpLaunchTime`):
  194 ms hasta terminar el lanzamiento y 212 ms hasta el primer idle; el
  segundo que se percibe desde el clic lo ponen la creación del proceso,
  el bote del icono del Dock y el primer arranque tras instalar, no la
  app. Afirmación autorizada: «arranca antes de que el icono deje de
  botar»; la cifra, siempre con el modelo de Mac
- **Qué no prometer**: «el más rápido» o «el mejor» sin comparar con
  método; funciones del ROADMAP aún no hechas; cifras no medidas en el
  Mac donde se afirman

## Transversal (toda fase)

- [x] Accesibilidad: VoiceOver operativo, respetar tamaño de texto del sistema — implementado (ver «v0.7.0: Accesibilidad»); queda la ronda manual de VoiceOver de Ernesto
- [x] Seguridad de los datos del usuario: nada que Marcus abra puede acabar reescrito dañado por el autoguardado (D11: binarios y conversiones con pérdida rechazados; fines de línea preservados). Cada fase que toque lectura o escritura lo re-comprueba con `-MarcusDebugSaveAfter`
- [x] CI en verde en cada push (`swift build` + `swift test`, ver DEPLOY.md); los presupuestos de rendimiento en release siguen siendo un paso local del checklist
- [x] Cero trabajo en el arranque que no sea imprescindible para teclear — auditado tras las Fases 2–6 (ver «Auditoría de arranque»); se re-audita en cada fase con `-MarcusDebugDumpLaunchTime` y, si hace falta detalle, xctrace

## No-objetivos (permanentes)

Sin workspaces obligatorios, sin sincronización propia, sin base de datos, sin
indexación permanente, sin plugins en el arranque, sin Electron ni web views en
la ruta de edición. Los archivos pertenecen al usuario.
