# Changelog

Todos los cambios notables de Marcus se documentan aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el versionado sigue [SemVer](https://semver.org/lang/es/). Mientras la
versión sea `0.x`, la API y el comportamiento pueden cambiar entre minors.

## [0.9.0] - 2026-10-03

Los tres primeros pasos acordados tras v0.8.0: pegar una URL sobre una
selección crea el enlace, menú Compartir nativo y exportar como RTF para
Word, Pages y TextEdit.

### Añadido

- Pegar una URL sobre una selección crea el enlace `[selección](url)`
  (ayuda de escritura, punto 1 tras v0.8.0). Con texto seleccionado y una
  URL en el portapapeles, ⌘V envuelve la selección en vez de sustituirla;
  el caret queda tras el enlace y ⌘Z lo deshace de una vez. Es una URL lo
  que tiene un esquema de la lista cerrada `http`, `https`, `ftp`, `ftps`,
  `mailto`, `tel` o `file` y nada de espacios (así `Hora:tarde` o
  `example.com` sin esquema se pegan tal cual, y `javascript:` nunca se
  enlaza); los espacios que rodean a la selección —el típico espacio final
  del doble clic— quedan fuera del enlace, y una URL con paréntesis
  desbalanceados va entre `<…>` para que CommonMark no la corte. **Pegado
  normal** cuando no hay selección, la selección abarca varias líneas,
  contiene corchetes (habría que escaparlos) o es ella misma una URL (se
  está sustituyendo, no etiquetando), y siempre en los formatos de texto
  plano honesto (Fase 6). Lógica pura en `MarcusCore` (`LinkPaste`, 19
  tests); en la app, una sobrescritura de `paste(_:)` que, si no procede,
  cede el pegado al sistema. Gancho `-MarcusDebugPaste
  "texto;loc,len;/out.json"`, que pega desde un portapapeles privado — el
  del usuario no se lee ni se toca — y vuelca texto, caret y si enlazó.
- Menú Compartir nativo (Archivo → Compartir → Compartir como HTML… /
  como PDF…, punto 2 tras v0.8.0): el HTML autocontenido o el PDF
  paginado que ya producen las exportaciones, ofrecidos por la hoja de
  compartir del sistema (`NSSharingServicePicker`) — Mail, Mensajes,
  AirDrop, Notas y lo que el usuario tenga — sin transporte propio. El
  archivo se escribe en una carpeta temporal **con el nombre del
  documento**, así que el destinatario recibe `Notas.pdf` y no un UUID; la
  hoja se ancla bajo la barra de título, donde la ponen las apps sin botón
  de compartir (TextEdit, Vista Previa). El PDF se genera antes de abrir
  la hoja por el mismo camino sin red de Exportar como PDF (`MarkdownPrinter`
  gana un callback de fin). Desactivado en los formatos de texto plano
  honesto, como las exportaciones. Gancho `-MarcusDebugShare
  "html|pdf;/out.json"`: vuelca el archivo ofrecido (ruta, bytes), los
  servicios que propuso el sistema y las ventanas visibles ajenas al
  documento (la hoja).
- Exportar como RTF (Archivo → Exportar como RTF… y Archivo → Compartir →
  Compartir como RTF…, punto 3 tras v0.8.0): el mismo `NSAttributedString`
  que pinta la preview, escrito por AppKit — sin Pandoc ni dependencias —,
  que Word, Pages y TextEdit abren con títulos, negrita, cursiva, tachado,
  listas, citas, código con su fondo, tablas y **enlaces** (campos
  `HYPERLINK`; los relativos se escriben tal cual, sin filtrar rutas del
  disco). Aspecto fijo de papel: la paleta clara del HTML exportado
  (`PreviewPalette.paper`), escala 1, sin zoom ni Dynamic Type — los
  colores dinámicos del sistema darían texto blanco en modo oscuro. Las
  fuentes privadas del sistema (`.AppleSystemUIFont…`), que ninguna otra
  app resuelve, se cambian por Helvetica Neue y Menlo conservando tamaño y
  negrita/cursiva. Las **imágenes viajan como su texto alternativo**
  (`[descripción]`): RTF no las lleva y RTFD es un paquete que Word no
  abre. El título del documento va a sus propiedades. Front matter
  omitido, como en todas las exportaciones; desactivado en texto plano
  honesto. `MarkdownRTFExporter` en MarcusPreview (10 tests de ida y
  vuelta); el renderer gana la opción `imagesAsText`. Gancho
  `-MarcusDebugExportRTF /out.rtf`, y `-MarcusDebugShare` acepta `rtf`.
  `.docx` queda como fase futura con escritor propio (ver ROADMAP): el de
  AppKit pierde enlaces e imágenes.

### Cambiado

- Guía integrada revisada contra la app: sección propia «Exportar y
  compartir» (HTML, PDF, RTF y Compartir, antes colgando de los atajos);
  «Lo esencial» cuenta que cada ventana vuelve con su vista previa y su
  esquema y cómo se tratan los cambios externos al archivo; ⌘0 junto a
  los demás atajos de zoom.

## [0.8.0] - 2026-10-02

Ayudas de escritura (sub/superíndices D17, zoom de texto D18, ortografía),
sesión que vuelve como se dejó, y una pasada de robustez: datos del
usuario (codificación sin pérdida, fines de línea preservados), camino de
apertura, vista previa e impresión sin red. Incluye además lo cerrado en
[0.7.0] (accesibilidad), que no llegó a publicarse como release.

### Añadido

- Sub/superíndices como ayuda de escritura (Format → Superscript `⌃⌘=` /
  Subscript `⌃⌘-`, decisión D17; *no* es una extensión del dialecto, D6
  queda intacto). Los comandos **transliteran la selección a los
  caracteres Unicode** de sub/superíndice (`2` → `²`, `2` → `₂`), no
  insertan marcadores: el archivo guarda Unicode plano, así que la
  preview, las exportaciones y Copiar como HTML no tocan nada y el
  resultado se ve igual en GitHub y en cualquier editor. Funcionan como
  **toggle**: si todo lo convertible de la selección ya está en esa forma,
  vuelve a ASCII; si no, convierte lo que falte (revertir normaliza a
  ASCII). **Sin selección** actúan sobre la palabra del caret, de modo que
  con el caret dentro de `H2O` el subíndice da `H₂O`. **Límite honesto**
  (documentado en la guía): solo convierten lo que Unicode tiene como
  sub/superíndice — los dígitos y los signos `+ - = ( )` completos en
  ambos sentidos, las letras solo en parte (las mayúsculas casi no tienen
  subíndice, y por eso la `H` y la `O` de `H₂O` no bajan); lo que no tiene
  forma se deja igual. Lógica pura en `MarcusCore` (`ScriptToggle`,
  hermana de `EmphasisToggle`); los mapas se escriben con escapes Unicode
  y un test recorre cada entrada para validar el ida y vuelta. 17 tests.
  Desactivados en los formatos de texto plano honesto (Fase 6), como
  Negrita/Cursiva.
- Zoom de texto in-app (View → Zoom In `⌘+` / Zoom Out `⌘-` / Actual Size
  `⌘0`, decisión D18): un factor global y persistido que agranda o reduce
  **el editor y la vista previa** —el contenido que lees y escribes, no la
  barra de recuento ni el outline— al instante y sin tocar el sistema.
  **Complementa** a Dynamic Type (v0.7.0) en vez de sustituirlo: aquél
  sigue el tamaño de texto del sistema (global, y solo al relanzar); este
  es tu palanca por-app, en caliente. Los dos se componen —
  `tamaño = base × escala del sistema × zoom` —, con tope en `[0.5, 3.0]`
  sobre una rejilla de 0.1 que no acumula deriva. `⌘0` vuelve al 100 %.
  Lógica pura en `MarcusCore` (`ZoomStep`, 8 tests); se aplica en vivo por
  la misma vía que el cambio de tema, así que el arranque no paga nada.

- Corrección ortográfica mientras se escribe: el subrayado rojo del
  sistema, en el idioma del texto, activado por defecto como en toda app
  de texto del Mac — el menú Edición no tenía el submenú estándar
  «Ortografía y gramática» y nada persistía la elección, así que una
  herramienta de escritura abría siempre sin ortografía. Ahora el submenú
  está (panel de ortografía ⌘:, Comprobar documento ahora ⌘;, comprobar
  mientras se escribe, gramática), el conmutador se persiste como ajuste
  (Ajustes → Otros ajustes, también desde el menú o el menú contextual del
  editor) y se aplica en vivo a todas las ventanas. Comprobar no es
  corregir: las sustituciones automáticas siguen apagadas porque corrompen
  el Markdown. La guía lo documenta.

- Idioma de la ortografía por app (Ajustes → Idioma de la ortografía):
  «Sistema» deja el corrector como lo tenga macOS — normalmente
  «Automático por idioma», que identifica el idioma párrafo a párrafo con
  un modelo estadístico y se equivoca con las líneas cortas llenas de
  símbolos: `# idyoma & ortografia` pasa por húngaro y queda sin marcar
  (medido con `NSSpellChecker`; TextEdit hace lo mismo). Un idioma fijo
  resuelve eso y se aplica solo a Marcus: el corrector compartido es por
  proceso y fijarlo por código no escribe ninguna preferencia global
  (verificado). La lista la da el sistema, con los nombres en el idioma
  del usuario; el cambio re-comprueba al instante las ventanas abiertas.
  `-MarcusSpellingLanguage es` como argumento; el volcado DumpDocState
  añade `spellingLanguage`.
- La sesión vuelve como se dejó: si la vista previa o el esquema estaban
  abiertos en una ventana, al relanzar Marcus (con las ventanas
  restauradas por el sistema) vuelven a estar abiertos en esa ventana.
  Montado sobre el estado restaurable de `NSWindow` que `NSDocument` ya
  usa para reabrir los documentos — ningún archivo propio, ningún ajuste
  global: cada ventana recuerda lo suyo (`DocumentWindow`). La
  restauración no anima ni anuncia a VoiceOver, porque nada cambia ante
  el usuario. Como en toda app del Mac, depende de «Cerrar ventanas al
  salir de una app» (Ajustes del Sistema → Escritorio y Dock): con esa
  opción activa, salir con ⌘Q cierra las ventanas y no hay nada que
  restaurar; ⌥⌘Q las conserva. Gancho `-MarcusDebugQuitAfter N` (salida
  limpia por `NSApp.terminate`, que guarda el estado) para verificarlo;
  verificado con el bundle `.app`, donde el sistema persiste el estado.

### Corregido

- El editor era siempre 780 pt más ancho que su panel, desde la 0.1.0: el
  scroll adoptaba el `NSTextView` (780 pt) con el clip aún a cero y, al
  tomar su frame, el autoresizing sumaba esos 780 encima. Consecuencias:
  las líneas largas se envolvían 780 pt más allá del borde derecho de la
  ventana (texto perdido por la derecha) y, en cuanto el esquema o la
  vista previa estrechaban el editor, el clip se desplazaba de lado para
  seguir al caret y las primeras letras de cada línea aparecían cortadas
  por la izquierda — lo que delató la restauración de paneles de esta
  versión. Ahora el ancho del editor se realinea con el clip al montarlo
  y lo sigue desde entonces: envuelve en el borde de la ventana y los
  paneles abren a sus anchos (esquema 220, editor 320, preview 358 en una
  ventana de 900). Verificado por geometría con los ganchos nuevos
  `-MarcusDebugTypeText "texto"` (teclea por `insertText`, `\n` es ⏎) y
  `-MarcusDebugSnapshot /ruta.png` (PNG de la ventana dibujado por la
  propia app, más `.json` de geometría del editor y `.constraints.txt`
  con las restricciones horizontales; sin permisos de grabación y sin
  capturar la pantalla del usuario).
- La recarga silenciosa por cambio externo (sin ediciones pendientes)
  perdía el caret y el scroll: reemplazar el texto los devolvía al
  principio del documento. Ahora se capturan antes de revertir y se
  restauran después, acotados al texto nuevo. Verificado con el volcado
  `-MarcusDebugDumpSyncState`, que añade `editorCaret` y `textLength`.
- Imprimir y Exportar PDF ya no tocan la red: el `WKWebView` que maqueta
  (D7) cargaba las imágenes remotas de un `<img>` en HTML crudo o de un
  `![](https://…)` — un píxel de seguimiento en una nota descargada
  avisaba a su servidor al imprimir. Ahora una lista de reglas de
  contenido bloquea todo esquema de red (`http`, `https`, `ws`, `ftp`); las
  imágenes locales llegan incrustadas como data URIs y no se ven
  afectadas, así que lo impreso coincide con la vista previa, que tampoco
  muestra imágenes remotas. De paso, el callback de fin de impresión, que
  AppKit invoca fuera del hilo principal al escribir un PDF sin panel,
  salta al hilo principal antes de liberar el web view.
- La vista previa volvía a leer y decodificar del disco todas las imágenes
  del documento en cada render — y hay un render tras cada pausa de
  300 ms al teclear —, el coste dominante en documentos con muchas
  imágenes. Ahora las imágenes decodificadas se guardan en una caché
  acotada (64 entradas) validada en cada consulta contra la fecha de
  modificación y el tamaño del archivo (un `stat`, no una decodificación):
  una imagen que cambia en disco se recarga sola. 3 tests.
- Los fines de línea del archivo se preservan de verdad (D11): un archivo
  con CRLF (Windows) o CR acababa mixto tras editar, porque nada
  normalizaba al leer y Return inserta `\n`. Ahora Marcus detecta el estilo
  dominante al abrir, trabaja en memoria solo con `\n` y restaura el estilo
  del archivo al guardar — también para un `\r\n` pegado desde otra app,
  que ya no puede convertirse en `\r\r\n`. Un archivo mixto queda uniforme
  en su estilo dominante al guardar. Lógica pura en `MarcusCore`
  (`LineEnding`, `TextFile`), 21 tests; verificado de punta a punta con el
  gancho nuevo `-MarcusDebugSaveAfter N` (guarda el documento frontal N
  segundos tras arrancar, para inspeccionar los bytes escritos).
- Seguridad de los datos al abrir: la decodificación con pérdida se
  descartaba en silencio. El fallback de detección de codificación
  ignoraba si la conversión había perdido caracteres, de modo que un
  archivo que no fuera UTF-8 ni se detectara bien se abría con caracteres
  sustituidos y el primer autoguardado escribía esa pérdida sobre el
  original; y con «Abrir cualquier archivo de texto» cualquier binario
  fuera de la lista de tipos rechazados (`.dat`, `.sqlite`…) «decodificaba»
  como Latin‑1. Ahora la detección solo admite conversiones sin pérdida,
  los datos con bytes NUL (sin BOM UTF‑16/32) se rechazan como binarios y
  el error lo dice claro: «Marcus no puede abrir este archivo: no es
  texto», con el motivo. UTF‑16/32 con BOM se siguen leyendo (y se guardan
  como UTF‑8 sin BOM, D11).
- Cada documento se resaltaba dos veces al abrir: una al leer el archivo y
  otra entera al cargar la vista del editor, que re-aplicaba el tema. Es
  coste directo del camino de apertura (presupuesto: 10 MB en menos de
  1 s). Además el primer pase ignoraba el zoom persistido (el tema nacía
  en 1,0) y el segundo lo corregía. Ahora el tema del resaltador nace con
  la paleta y el zoom vigentes, el pase de la lectura ya es el definitivo
  y la vista solo fija sus propios colores y atributos de tecleo.
- En modo vista previa a ventana completa, cualquier escritura en
  UserDefaults disparaba un fundido cruzado: la notificación de cambio de
  defaults se trataba como cambio del modo de preview sin comprobarlo, y en
  modo completo eso es una instantánea de toda la vista más 250 ms de
  animación. Lo provocaban ⌘+/⌘−, mostrar el recuento o cerrar un panel de
  guardar (los paneles escriben sus propios defaults). Ahora solo un cambio
  real del modo re-aplica la disposición, como ya se hacía con tema y zoom.
- Zoom de texto (⌘+/⌘−/⌘0), Mostrar recuento de palabras y Copiar como
  HTML dejaban de funcionar cuando el foco no estaba en el editor: las
  acciones vivían en el controlador del editor, que no está en la cadena
  de respuesta del `NSTextView` de la vista previa ni del esquema. En modo
  ventana completa el foco cae en la preview por diseño, así que el zoom
  quedaba desactivado justo donde más se lee. El zoom pasa al delegado de
  la app (solo escribe un ajuste y cada vista reacciona sola); recuento y
  Copiar como HTML pasan al controlador del split, que sí está en todas
  las cadenas. De paso, Aumentar acepta también `⌘=` (ítem oculto con
  atajo activo): en teclados US el `+` exige Shift y `⌘=` es la convención
  de Safari y Xcode.
- Guardar un documento abierto como texto plano honesto (Fase 6, D15)
  conservaba mal la extensión: un `.html` (o `.css`, `.log`… — cualquier
  formato que Marcus no declara, abierto con «Abrir cualquier archivo de
  texto») se abría con el tipo `public.plain-text`, y al guardar
  `NSDocument` forzaba la extensión de ese tipo y **renombraba
  `pagina.html` a `pagina.txt`**, moviendo el archivo del usuario en
  silencio. Ahora los guardados *in situ* (⌘S y autoguardado) conservan la
  extensión del propio archivo — el tipo sigue al archivo (D11/D15), los
  bytes son el mismo UTF-8 —, así que un `.html` se guarda como `.html`.
  «Guardar como» y los documentos nuevos sin título mantienen el
  comportamiento estándar (por defecto `.md`).
- La vista previa renderizaba las tablas ignorando la alineación de columnas
  (todo a la izquierda, aunque el Markdown pidiera `:--:` o `--:`) y aplanaba
  el marcado dentro de las celdas (negrita, cursiva, enlaces y código
  quedaban como texto plano). Ahora la rejilla monoespaciada **honra la
  alineación** (izquierda/centro/derecha) y **conserva el formato de celda**,
  renderizando cada celda con la fuente monoespaciada para que las columnas
  sigan cuadrando por carácter. Sigue siendo una rejilla mono —TextKit 2 no
  tiene tablas nativas; los bordes y la tipografía proporcional quedan para
  un posible camino con `NSTextTable`—. 5 tests nuevos.

## [0.7.0] - 2026-07-12

Accesibilidad (transversal abierto desde la Fase 0): VoiceOver en las
vistas propias y Dynamic Type de punta a punta.

> Nota (2026-10-02): esta versión quedó cerrada aquí pero nunca se etiquetó
> ni se publicó como release en GitHub; su contenido sale con la 0.8.0.

### Añadido

- VoiceOver en las vistas propias: `accessibilityLabel`, roles y orden de
  foco lógico. Las celdas del outline dicen su nivel de encabezado
  («Nivel 2, Título de sección») bajo la etiqueta de la barra lateral
  («Esquema del documento»); la barra de recuento se lee como una frase
  limpia («Markdown: 26 palabras, 194 caracteres») en vez de deletrear
  los separadores «·»; el editor y el `NSTextView` de solo lectura de la
  preview se nombran distinto («Editor» / «Vista previa renderizada»)
  para no confundirse al oído; el ojo del modo ventana completa es
  alcanzable y se anuncia como «Vista previa a ventana completa» — el
  único indicio en pantalla completa de macOS, donde la barra de título
  se auto-oculta. El orden de foco de los paneles es el visual
  (outline → editor → preview) y el foco inicial cae en el editor (en la
  preview cuando ocupa la ventana completa). Al mostrar u ocultar la
  preview o el outline, un anuncio de VoiceOver dice qué cambió («Vista
  previa visible/oculta», «Esquema visible/oculto»), porque el cambio de
  disposición es mudo de otro modo. Gancho `-MarcusDebugDumpA11y
  /ruta.json`: vuelca en JSON las etiquetas de accesibilidad de las
  vistas propias, el último anuncio y el orden de paneles, para
  verificar la maquinaria sin VoiceOver (la ronda de VoiceOver real, que
  es manual, queda para Ernesto).
- Dynamic Type: el editor, la UI (barra de recuento, celdas y altura de
  fila del outline) y la vista previa siguen el tamaño de texto del
  sistema. macOS 15 (Sequoia) añadió el control de tamaño de texto en
  Accesibilidad → Pantalla; `NSFont.preferredFont(forTextStyle:.body)`
  escala con él, y Marcus deriva de ahí un único factor
  (`DynamicType`) con el que multiplica sus propias fuentes —
  monoespaciada en el editor, tipografía de lectura en la preview— sin
  renunciar a ellas. En macOS 14, o al tamaño por defecto, el factor es
  1: nada cambia hasta que el usuario amplía el texto del sistema. El
  factor de la preview se captura en el hilo principal y se pasa al
  render, que sigue fuera de él. Gancho `-MarcusDebugTextScale 1.5`:
  fuerza el factor (ningún argumento de lanzamiento puede tocar el ajuste
  del sistema), y el volcado de `-MarcusDebugDumpA11y` añade
  `dynamicTypeScale` y `previewFontAtStart` para verificar el escalado de
  punta a punta.

### Cambiado

- Guía integrada: nota de accesibilidad (inglés y español) en «Hazlo tuyo
  (funciones del sistema)», junto al idioma y los atajos por app — que
  Marcus funciona con VoiceOver y respeta el tamaño de texto del sistema
  (relanzar para aplicar un cambio).

## [0.6.0] - 2026-07-07

Fases 6 y 7: Marcus abre cualquier texto (opt-in) y trata con tolerancia
el front matter YAML de los documentos Markdown.

### Añadido

- Front matter YAML en el editor (Fase 7, D16): si la línea 1 del
  archivo es exactamente `---`, el bloque hasta el cierre `---` se
  atenúa con la tinta terciaria del tema — metadatos, no texto — y no
  se escanea como Markdown por dentro (un `# clave:` ahí no es un
  encabezado ni abre nada). Detección puramente posicional, sin parser
  de YAML ni validación; sin cierre no hay bloque. El outline lo ignora
  solo. 19 tests de la lógica (clasificación, re-escaneo incremental,
  recorte, CRLF).
- La vista previa, Exportar HTML/PDF, Imprimir, Copiar como HTML y el
  recuento de palabras omiten el front matter (Fase 7): los metadatos no
  son parte del documento legible. Todos los caminos HTML pasan por la
  misma puerta (`MarkdownHTMLExporter.body`) y la preview recorta antes
  de parsear; las anclas del sync editor→preview conservan los números
  de línea del documento completo, así que el seguimiento del caret no se
  desplaza. El recuento excluye el bloque solo donde aplica el trato
  Markdown (`.md`/`.txt`); un formato de texto plano honesto que empiece
  por `---` cuenta todo. 8 tests (renderer, exportador y recuento,
  incluido el bloque sin cerrar).
- Gancho de auditoría de arranque `-MarcusDebugDumpLaunchTime /ruta.json`:
  vuelca en JSON los milisegundos desde el exec del proceso (hora de
  arranque del kernel, sin profiler de por medio) hasta el final del
  lanzamiento y hasta el primer idle del main loop — el editor listo
  para teclear. Deja la comprobación del presupuesto de <500 ms al
  alcance de un comando en cada fase (transversal del ROADMAP).
- «Abrir cualquier archivo de texto» (Ajustes → Otros ajustes,
  desactivado por defecto): con el ajuste activo, el panel de abrir
  admite cualquier archivo y los tipos que Marcus no declara (HTML,
  extensiones desconocidas como `.conf`) se resuelven como texto plano
  vía `MarcusDocumentController` (subclase instalada como controlador
  compartido desde `main.swift`). Las categorías que nunca son texto
  (imagen, audio/vídeo, archivo comprimido, ejecutable, tipografía,
  PDF) se siguen rechazando aunque el ajuste esté activo — el fallback
  de codificación con pérdida podría mostrar basura que el autoguardado
  reescribiría sobre el archivo. Desactivado, todo sigue como siempre:
  el código fuente y los logs ya abrían por conformidad con
  `public.plain-text`. El guardado no necesita ajuste: el tipo sigue al
  archivo.
- La vista previa (⌘⇧P) de un documento no-Markdown muestra un mensaje
  honesto en vez de render: «Este formato (X) no admite vista previa.
  Marcus es una herramienta primaria para texto, optimizada para
  Markdown» — con la tinta secundaria del tema y el nombre del formato
  del sistema. Sin anclas, el sync editor→preview queda inerte solo.
- Texto plano honesto para los formatos no-Markdown (Fase 6): el
  resaltado se apaga (atributos base del tema, sin estilos Markdown);
  Exportar HTML/PDF, Imprimir, Copiar como HTML, Negrita/Cursiva y el
  outline se desactivan en los menús; la continuación de listas queda
  inerte. `.md` y `.txt` conservan íntegro su comportamiento de la
  Fase 4. «Guardar como» puede mover un documento entre ambos mundos
  (`.js` → `.md`): el estilo y los menús siguen al archivo. El volcado
  `-MarcusDebugDumpDocState` incluye ahora `supportsMarkdown`,
  `fontAtStart` y `previewText` para verificarlo sin captura.
- Indicador de formato del documento (Fase 6, decisión D15): la barra de
  recuento antepone qué es el archivo («Markdown · Palabras: … ·
  Caracteres: …») y, para documentos no-Markdown, la ventana lo anuncia
  como subtítulo — un `.txt` se presenta como «Texto plano», un `.js`
  como «JavaScript» (nombre del sistema, ya localizado; la extensión en
  mayúsculas como último recurso). El subtítulo «Vista previa» del modo
  ventana completa manda mientras la preview está visible y el formato
  vuelve al ocultarla. Sigue a «Guardar como»: el tipo sigue al archivo.
  La clasificación (`DocumentFormat` en MarcusCore) va solo por
  extensión, nunca por contenido; 8 tests. Ganchos:
  `-MarcusDebugDumpDocState /ruta.json` vuelca formato, subtítulo y
  barra de recuento sin captura de pantalla, y `-MarcusDebugNoActivate
  YES` lanza la app sin activarla (no roba el foco durante la
  verificación).

### Cambiado

- Guía integrada: sección nueva sobre el front matter YAML (inglés y
  español), junto a la raya horizontal con la que ya no se confunde.
- La vista previa y el outline construyen sus vistas la primera vez que
  se muestran, no al abrir la ventana (auditoría de arranque tras la
  Fase 6): un panel colapsado ya no paga ni su jerarquía de vistas en el
  camino de tecleo. Sin efecto medible en el arranque templado (~210 ms,
  dominado por AppKit), pero alinea el código con el transversal del
  ROADMAP y ahorra memoria por ventana.
- Manifiesto ajustado a la Fase 6 (D15): «herramienta primaria para
  texto, optimizada para Markdown» — README, cabecera del ROADMAP y
  guía integrada (que ahora documenta el ajuste nuevo, el trato honesto
  de los otros formatos y el indicador en la barra de recuento).

## [0.5.0] - 2026-07-06

Fase 5 cerrada: preview conectada — la vista previa cuenta en qué modo
está y sigue al editor.

### Añadido

- Indicador del modo vista previa a ventana completa: mientras está
  visible, la barra de título muestra el subtítulo «Vista previa» junto
  al nombre del documento, y un icono discreto (ojo, tintado con la
  tinta secundaria del tema) queda fijo arriba a la derecha del
  contenido — necesario en pantalla completa de macOS, donde la barra
  de título se auto-oculta y el subtítulo no se ve (detectado en la
  ronda manual). Ambos desaparecen al ocultar la preview o al cambiar
  a modo panel (donde el editor sigue a la vista y no hacen falta).
- Sincronización editor → vista previa (modo panel): clic o caret en el
  editor desplaza la preview a la sección correspondiente, por anclas
  de encabezado — el renderizador marca cada encabezado con su línea de
  origen y el editor resuelve la sección con el scan del resaltador,
  sin re-parsear nada. Solo se desplaza cuando cambia la sección
  destino, para no pelear con el scroll manual de la preview; en
  ventana completa no aplica (no hay editor a la vista). 16 tests de la
  lógica (anclas ATX/setext/citas, caret→línea, bordes CRLF). Ganchos:
  `-MarcusDebugCaretAt N` coloca el caret en el offset N tras el primer
  render y `-MarcusDebugDumpSyncState /ruta.json` vuelca el estado del
  scroll y las anclas para verificación sin captura de pantalla.

## [0.4.0] - 2026-07-06

Fase 4 cerrada (versatilidad, sin perder el minimalismo): texto plano,
apertura en pestañas opcional y Copiar como HTML. Incluye además lo
hecho tras v0.3.0 en la Fase 3 (navegación y productividad).

### Añadido

- Texto plano: Marcus abre y guarda `.txt` además de `.md`. El tipo
  sigue al archivo — un `.txt` se guarda como `.txt` —, los documentos
  nuevos siguen siendo Markdown y el panel de guardado permite elegir
  el formato (popup «File Format»). Sin adivinar la extensión por
  contenido: el panel es la confirmación. Ganchos:
  `-MarcusDebugOpenFile /ruta1,/ruta2` abre archivos sin interacción y
  `-MarcusDebugShowSaveAs YES` lanza «Guardar como» sobre el documento
  frontal.
- «Abrir documentos en pestañas» (Ajustes → Otros ajustes, desactivado
  por defecto): los documentos se abren como pestañas de una única
  ventana en vez de ventanas sueltas. La ventana nueva se acopla
  explícitamente a la ventana de documento frontal (`addTabbedWindow`):
  el emparejado automático de AppKit solo funciona entre ventanas
  creadas ya con `tabbingMode` preferido, y dejaba fuera a las abiertas
  antes de activar el ajuste. Desactivado, manda el ajuste global del
  sistema, como hasta ahora. Gancho: `-MarcusDebugOpenFileDelayed
  /ruta` abre un documento 2,5 s tras el arranque (simula la apertura
  desde Finder con la app corriendo).
- Copiar como HTML (Edición → Copiar como HTML, ⌥⌘C): la selección — o
  el documento entero si no hay selección — va al portapapeles como
  HTML del exportador (fragmento sin plantilla ni CSS, para que el
  destino aplique su propio estilo), con el Markdown original como
  respaldo de texto plano. Render fuera del hilo principal. 1 test del
  contrato del fragmento. Gancho: `-MarcusDebugCopyHTML YES`.

- El panel «Acerca de Marcus» enlaza al repositorio
  (github.com/cubakumori/marcus). Gancho de verificación:
  `-MarcusDebugShowAbout YES`.
- La vista previa sigue el tema del editor en lo básico: fondo y tintas
  de la paleta activa (System/Sepia/Midnight), manteniendo su tipografía
  de lectura. Se re-renderiza en vivo al cambiar el tema en ⌘,.
- Outline del documento (⌘⇧O): barra lateral con el índice de
  encabezados, sangrado por nivel; clic para saltar al encabezado
  (con indicador de búsqueda). Derivado del scan del resaltador — en
  memoria, por documento, sin re-parsear ni indexar nada. 9 tests de la
  derivación del índice. Gancho: `-MarcusDebugShowOutline YES`.
- Ayudas de escritura: ⏎ continúa listas (viñetas, numeradas con
  incremento, tareas; un ítem vacío cierra la lista) — opt-in en
  Ajustes, desactivada por defecto. Menú Format nuevo con Negrita (⌘B)
  y Cursiva (⌘I) que envuelven/des-envuelven la selección y componen
  entre sí. 25 tests de la lógica. Gancho: `-MarcusDebugShowSettings
  YES` abre Ajustes.
- Visualización → Tema: el tema del editor (Sistema/Sepia/Medianoche)
  también se cambia desde el menú, con marca en el activo — mismo ajuste
  que en ⌘,.
- Recuento de palabras y caracteres (View → Show Word Count, persistido):
  barra discreta bajo el editor. Recuento lingüístico — los marcadores
  Markdown no cuentan como palabras — con debounce y fuera del hilo
  principal; oculta no cuesta nada. 4 tests.
- Abrir enlaces con ⌘-clic: `[texto](url)` abre el destino (los
  relativos, contra la carpeta del documento). El clic normal sigue
  editando, como debe ser en un editor.
- Guía integrada (Ayuda → Guía de Marcus, ⌘⇧H): manual y demo en vivo a la
  vez, en el idioma del sistema (en/es), abierta en solo lectura.
  Documenta la sintaxis soportada, los atajos y los ajustes, incluidos
  los mecanismos del sistema para personalizar atajos e idioma por app.
  Gancho: `-MarcusDebugShowGuide YES`.

### Cambiado

- Ajustes: las opciones sueltas se agrupan bajo el acápite «Otros
  ajustes:» para no confundirse con el grupo de tema.

### Corregido

- La vista previa en modo ventana completa entra y sale con un fundido
  cruzado en vez de deslizarse (⌘⇧P, ambos sentidos): al animar los
  paneles, sus anchos nunca sumaban el de la ventana y ambas
  transiciones dejaban ver un destello de ventana partida con una
  franja en blanco. Es un cambio de modo, no un panel que se asoma —
  el fundido lo cuenta mejor. El panel lateral conserva su
  deslizamiento. Implementado con una instantánea que se desvanece
  (`NSAnimationContext`), nunca con `CATransition` sobre capas que
  gestiona AppKit (desprende la superficie de la ventana del window
  server). Gancho: `-MarcusDebugTogglePreviewAfter N` conmuta la
  preview N segundos tras abrir la ventana, para capturar
  transiciones.

## [0.3.0] - 2026-07-03

Fase 2 cerrada: vista previa nativa, exportación (HTML, PDF, imprimir),
UI localizada (inglés y español) y temas del editor.

### Añadido

- Vista previa nativa (⌘⇧P): panel dividido con render de lectura
  (tipografía proporcional, listas, tareas, citas, código, tablas v1 en
  rejilla, imágenes locales, enlaces). Construida sobre `swift-markdown`
  (AST) + TextKit, sin web views. El parseo y la construcción del texto
  ocurren en segundo plano con debounce de 300 ms; con la preview oculta el
  coste es cero. Nuevo target `MarcusPreview` con 15 tests del renderizador.
- Ventana de Ajustes (⌘,) en SwiftUI con la primera preferencia: dónde se
  muestra la preview — panel lateral (por defecto) o ventana completa
  (oculta el editor mientras está visible). Cambio aplicado en vivo.
- Gancho de verificación automatizada: `-MarcusDebugShowPreview YES` como
  argumento de lanzamiento abre la preview sin interacción.
- Exportar HTML (File → Export as HTML…, ⌘⇧E): un único archivo
  autocontenido — plantilla mínima, CSS embebido con modo claro/oscuro
  (`prefers-color-scheme`) e imágenes locales incrustadas como data URIs.
  Sin scripts ni recursos externos. El render ocurre fuera del hilo
  principal. 21 tests del exportador.
- Exportar PDF (File → Export as PDF…) e imprimir (⌘P): mismo HTML que la
  exportación, maquetado por un `WKWebView` creado bajo demanda solo como
  motor de layout — JavaScript desactivado, nunca en la ruta de edición,
  liberado al terminar (decisión D7). PDF paginado con papel blanco
  independiente de la apariencia. Gancho de verificación:
  `-MarcusDebugExportPDF /ruta/salida.pdf`.
- Temas del editor (Ajustes → Editor theme): System (colores semánticos,
  sigue claro/oscuro), Sepia (papel cálido) y Midnight (oscuro fijo de
  alto contraste). Cambio aplicado en vivo re-resaltando el documento;
  persistido entre lanzamientos.
- Licencia: AGPL-3.0-or-later (`LICENSE`, decisión D13 del ROADMAP).
- i18n (decisión D14): toda la UI (menús, ajustes, diálogos) localizada
  con String Catalogs — inglés base, español como primera localización,
  siguiendo el idioma del sistema. Los `.xcstrings` son la fuente
  editable y `scripts/compile-strings.sh` genera los `.lproj` commiteados
  (`swift build` aún no compila catálogos). El binario declara
  `CFBundleLocalizations` y el script del DMG copia los bundles de
  recursos al .app.

### Cambiado

- Nuevo icono de la aplicación («Md» en serifa amarilla sobre negro):
  `Resources/marcus.icns` y `Resources/marcus.png` (logo del README).
- README reescrito en inglés y actualizado al estado de la Fase 2.

## [0.2.0] - 2026-07-03

Fase 1 cerrada: el editor es rápido, seguro con los archivos y completo
para el uso diario. Restauración de sesión y cambios externos verificados.

### Añadido

- `scripts/build-dmg.sh`: genera `dist/Marcus.app` (binario universal
  arm64 + x86_64, firmado ad-hoc) y `dist/Marcus-X.Y.Z.dmg`.
- Icono de la aplicación (`Resources/marcus.icns`), incluido en el bundle
  por el script de build; logo en el README.
- Re-escaneo incremental del resaltado: cada pulsación re-escanea solo desde
  la línea editada y se re-empalma con el escaneo anterior. En un documento
  de 10 MB, de 58 ms a ~4 ms por pulsación (presupuesto: 16 ms).
- Detección de cambios externos al archivo abierto: recarga silenciosa si no
  hay ediciones sin guardar; diálogo conservar/recargar si las hay.
- Conmutador de apariencia (View → Appearance: System/Light/Dark),
  persistido entre lanzamientos.
- Tests de rendimiento contra los presupuestos del ROADMAP (verificados en
  release, bloqueantes) y tests de propiedad: 400 ediciones aleatorias con
  equivalencia incremental/completo y documento de tortura.

## [0.1.0] - 2026-07-02

Primer esqueleto funcional (Fase 0 completa + grueso de la Fase 1).

### Añadido

- Paquete SwiftPM con tres targets: `MarcusCore` (lógica pura), `Marcus`
  (app AppKit) y tests. `swift build` / `swift test` sin proyecto Xcode.
- Escáner Markdown por líneas en `MarcusCore`: encabezados ATX, bloques de
  código (fences ``` y ~~~, indentado), citas, listas ordenadas y no
  ordenadas, separadores temáticos, y spans inline (código, negrita, cursiva,
  enlaces, marcadores estructurales). 25 tests unitarios.
- App de documentos `NSDocument`: nuevo, abrir, guardar, guardar como,
  revertir, Open Recent, autoguardado y versiones (`autosavesInPlace`).
- Editor `NSTextView` sobre pila TextKit 2 explícita, con resaltado
  incremental por diff de líneas y colores semánticos del sistema (modo
  claro/oscuro automático).
- Deshacer/rehacer enlazado al undo manager del documento (estado "editado"
  y save points coherentes).
- Buscar y reemplazar con la find bar nativa (búsqueda incremental).
- Lectura UTF-8 con o sin BOM y detección de codificación como fallback;
  escritura siempre UTF-8 sin BOM.
- Sustituciones automáticas de texto desactivadas (comillas y guiones
  "inteligentes" corrompen el Markdown).
- Menús y atajos de teclado estándar completos.
- Info.plist embebido en el binario (`__info_plist`) con los tipos de
  documento Markdown (`.md`, `.markdown`, `.mdown`).
- Documentación: `ROADMAP.md` con registro de decisiones (D1–D12),
  presupuestos de rendimiento y fases.
