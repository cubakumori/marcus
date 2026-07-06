# Changelog

Todos los cambios notables de Marcus se documentan aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el versionado sigue [SemVer](https://semver.org/lang/es/). Mientras la
versión sea `0.x`, la API y el comportamiento pueden cambiar entre minors.

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
