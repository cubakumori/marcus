# Changelog

Todos los cambios notables de Marcus se documentan aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el versionado sigue [SemVer](https://semver.org/lang/es/). Mientras la
versión sea `0.x`, la API y el comportamiento pueden cambiar entre minors.

## [Sin publicar]

Fase 6 implementada (pendiente de release): Marcus abre cualquier texto.
Fase 7 en curso: front matter YAML tolerante.

### Añadido

- Front matter YAML en el editor (Fase 7, D16): si la línea 1 del
  archivo es exactamente `---`, el bloque hasta el cierre `---` se
  atenúa con la tinta terciaria del tema — metadatos, no texto — y no
  se escanea como Markdown por dentro (un `# clave:` ahí no es un
  encabezado ni abre nada). Detección puramente posicional, sin parser
  de YAML ni validación; sin cierre no hay bloque. El outline lo ignora
  solo. 19 tests de la lógica (clasificación, re-escaneo incremental,
  recorte, CRLF).
- La vista previa, Exportar HTML/PDF, Imprimir y Copiar como HTML
  omiten el front matter (Fase 7): los metadatos no son parte del
  documento legible. Todos los caminos HTML pasan por la misma puerta
  (`MarkdownHTMLExporter.body`) y la preview recorta antes de parsear;
  las anclas del sync editor→preview conservan los números de línea del
  documento completo, así que el seguimiento del caret no se desplaza.
  5 tests (renderer y exportador, incluido el bloque sin cerrar).
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
