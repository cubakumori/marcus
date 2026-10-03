# Guía de Marcus

Bienvenido. Este documento es a la vez el manual y una demo en vivo:
pulsa ⌘⇧P para verlo renderizado al lado, y ⌘⇧O para navegarlo desde el
esquema. Se abre en solo lectura — tus archivos nunca se tocan.

## Lo esencial

Marcus es una herramienta primaria para texto, optimizada para
Markdown. Abre, edita y guarda archivos Markdown planos (`.md`) y texto
plano (`.txt`) — y, si activas «Abrir cualquier archivo de texto» en
Ajustes, cualquier otro formato de texto (HTML, CSS, logs, archivos de
configuración…) *como texto*: sin resaltado, sin vista previa, sin
fingir. El tipo sigue al archivo — un `.txt` se guarda como `.txt` —,
los documentos nuevos son Markdown y el panel de guardado permite
elegir el formato. La barra de recuento y, para archivos no-Markdown,
el subtítulo de la ventana dicen siempre qué estás editando. Nada se
importa, indexa ni convierte: el archivo en disco es la única verdad.
Los archivos se leen como UTF-8 (UTF-16/32 con marca de orden de bytes,
y codificaciones antiguas cuando la conversión no pierde nada) y se
guardan siempre como UTF-8 sin BOM; los fines de línea del archivo (LF,
CRLF o CR) se conservan. Los datos binarios se rechazan en vez de
abrirse como basura.
El autoguardado, las versiones y la restauración de sesión funcionan
como en cualquier app nativa del Mac; cada ventana vuelve con su vista
previa y su esquema como los dejaste. Si otra app cambia el archivo
abierto, Marcus lo recarga sin más cuando no tienes cambios sin guardar,
y te pregunta si los tienes.

## Markdown, con ejemplos

### Énfasis

El texto puede ir en **negrita**, *cursiva*, ~~tachado~~ o `código en
línea`.

### Superíndices y subíndices

El menú Formato convierte la selección en caracteres Unicode de super o
subíndice: `2` pasa a `²` (⌃⌘=) o a `₂` (⌃⌘-). Sin selección actúa sobre
la palabra que rodea el caret, así que con el caret dentro de `H2O` el
subíndice da `H₂O`. Aplicado de nuevo sobre texto ya convertido, lo
devuelve a la normalidad.

Son caracteres normales, no marcado: el archivo sigue siendo portable y
se ve igual en GitHub o donde sea. El matiz es el propio límite de
Unicode — solo se convierte lo que *tiene* forma de super o subíndice.
Los dígitos y los signos `+ - = ( )` están completos; las letras solo en
parte (las mayúsculas casi no tienen subíndice, y por eso la `H` y la `O`
de `H₂O` se quedan igual). Lo que no tiene forma se deja tal cual.

### Listas

1. Elemento numerado
2. Otro más
   - viñeta anidada

- [x] Una tarea hecha
- [ ] Una tarea pendiente

### Citas y código

> Una cita ocupa
> las líneas que haga falta.

```swift
let respuesta = 42  // código con fence, con lenguaje
```

### Tablas y enlaces

| Columna | Alineada |
|:--------|---------:|
| izquierda | derecha |

Un [enlace](https://example.com) se abre con ⌘-clic — el clic normal lo
edita, como corresponde en un editor. Los enlaces e imágenes relativos
se resuelven contra la carpeta del documento.

Para crear uno, selecciona el texto y pega la URL (⌘V): la selección se
convierte en `[texto](url)` en vez de sustituirse. Solo salta con una URL
de verdad (`https://…`, `mailto:…` y similares — no un `example.com` a
secas) y solo sobre una selección de una línea; en cualquier otro caso se
pega como siempre, y ⌘Z deshace el enlace de una vez.

Para añadir una imagen, Formato → Insertar imagen… (⌘⇧I, también con
clic derecho) te deja elegir una o varias; o cópialas en Finder (⌘C) y
pégalas aquí (⌘V); o arrástralas sobre el texto. Cada una queda como
`![nombre](ruta)`, con la ruta relativa a la carpeta del documento y el
nombre seleccionado para que escribas encima una descripción de verdad —
o, si tenías texto seleccionado, ese texto pasa a ser la descripción. La
imagen se queda donde está: Marcus no copia nada. Un documento nuevo aún
no tiene carpeta, así que Marcus te pide guardarlo antes.

---

La línea horizontal de arriba es `---` en su propia línea.

### Front matter YAML

Si la **primera línea del archivo** es exactamente `---`, el bloque
hasta el siguiente `---` se trata como metadatos (el «front matter» de
Jekyll, Hugo u Obsidian): en el editor se atenúa y no se interpreta
como Markdown, y la vista previa, las exportaciones, Copiar como HTML y
el recuento de palabras lo omiten. Marcus no valida el YAML — el bloque
es tuyo. Sin la línea
de cierre no hay bloque: un documento que empieza con una raya
horizontal sigue siendo Markdown normal.

## Atajos de teclado

| Atajo | Acción |
|:------|:-------|
| ⌘⇧P | Mostrar / ocultar la vista previa |
| ⌘⇧O | Mostrar / ocultar el esquema |
| ⌘⇧E | Exportar como HTML (un único archivo autocontenido) |
| ⌥⌘C | Copiar la selección (o el documento entero) como HTML |
| ⌘P | Imprimir, o guardar como PDF paginado |
| ⌘B / ⌘I | Negrita / cursiva sobre la selección |
| ⌃⌘= / ⌃⌘- | Superíndice / subíndice sobre la selección (Unicode) |
| ⌘V sobre una selección | Con una URL en el portapapeles: convierte la selección en enlace |
| ⌘⇧I | Insertar imagen (también con clic derecho, ⌘V de imágenes copiadas en Finder o arrastrando) |
| ⌘+ (o ⌘=) / ⌘- | Ampliar / reducir el texto del editor y la vista previa |
| ⌘0 | Volver el zoom del texto al 100 % |
| ⌘: / ⌘; | Panel de ortografía / comprobar documento ahora |
| ⌘, | Ajustes |
| ⌘F | Buscar; ⌥⌘F buscar y reemplazar |
| ⌘⇧H | Esta guía |

## Exportar y compartir

Archivo → Exportar como HTML… (⌘⇧E) escribe un único archivo
autocontenido: estilos e imágenes locales dentro, claro u oscuro según
quien lo abra. Archivo → Exportar como PDF… escribe el PDF directamente, sin pasar por
el diálogo de impresión. Como la vista previa, imprimir y el PDF nunca
descargan nada de la red: las imágenes locales van incrustadas y las
remotas se omiten.

Archivo → Exportar como RTF… escribe un documento que Word, Pages y
TextEdit abren con su formato: títulos, negrita y cursiva, listas, código
y enlaces. Sale siempre sobre página clara, sea cual sea tu tema o zoom, y
las imágenes viajan como su descripción (el texto entre los corchetes de
`![…]`).

Archivo → Compartir entrega ese mismo HTML, PDF o RTF a la hoja de
compartir del sistema — Mail, Mensajes, AirDrop, Notas y lo que tengas —,
con el nombre del documento.

## Ajustes que conviene conocer

- **Vista previa**: panel lateral o ventana completa (Ajustes, ⌘,). En
  panel, la vista previa sigue al cursor del editor por secciones; en
  ventana completa, la barra de título y un ojo discreto arriba a la
  derecha indican que el editor está oculto.
- **Tema del editor**: Sistema, Sepia o Medianoche — también en
  Visualización → Tema. La vista previa sigue el tema.
- **Apariencia**: claro / oscuro / sistema, en Visualización → Apariencia.
- **Comprobar la ortografía al escribir**: activado por defecto — el
  subrayado rojo del sistema, en el idioma del texto; nunca se corrige
  nada a tus espaldas (las comillas tipográficas y la autocorrección
  siguen apagadas: corrompen el Markdown). Desactívalo en Ajustes o en
  Edición → Ortografía y gramática, donde también están el panel de
  ortografía (⌘:) y Comprobar documento ahora (⌘;).
- **Idioma de la ortografía**: «Sistema» por defecto — normalmente el
  «Automático por idioma» de macOS, que adivina el idioma párrafo a
  párrafo y puede equivocarse con una línea corta llena de símbolos (un
  encabezado como `# idyoma & ortografia` pasa por húngaro y queda sin
  marcar). Elige un idioma fijo en Ajustes y Marcus lo comprueba todo en
  él, sin tocar el ajuste del sistema ni las demás apps.
- **Continuar listas al pulsar ⏎**: desactivado por defecto; actívalo en
  Ajustes y ⏎ continuará tus listas (un elemento vacío cierra la lista).
- **Abrir documentos en pestañas**: desactivado por defecto; actívalo en
  Ajustes y los documentos se abrirán como pestañas de una única ventana
  en vez de ventanas sueltas.
- **Abrir cualquier archivo de texto**: desactivado por defecto;
  actívalo en Ajustes y el panel de abrir admitirá cualquier formato de
  texto — editado como texto plano honesto, guardado como lo que ya
  era e impreso (⌘P) como texto monoespaciado, con las líneas largas
  partidas al borde de la página. Los formatos que nunca son texto (imágenes, audio, archivos
  comprimidos…) se siguen rechazando.
- **Recuento de palabras**: Visualización → Mostrar recuento de
  palabras. La barra dice además el formato del documento.

## Hazlo tuyo (funciones del sistema)

- **Idioma**: Marcus sigue el idioma del sistema (inglés/español). Para
  cambiarlo solo en Marcus: Ajustes del Sistema → General → Idioma y
  región → Aplicaciones → «+».
- **Atajos personalizados**: Ajustes del Sistema → Teclado → Funciones
  rápidas de teclado → Atajos de app permite redefinir cualquier
  elemento de menú por su título exacto.
- **Accesibilidad**: Marcus funciona con VoiceOver — el esquema (cada
  encabezado dice su nivel), la barra de recuento, el editor, la vista
  previa y el indicador de ventana completa están etiquetados, y mostrar
  u ocultar la vista previa o el esquema se anuncia. También respeta el
  tamaño de texto del sistema (Ajustes del Sistema → Accesibilidad →
  Pantalla → Tamaño de texto): el editor, la interfaz y la vista previa
  crecen con él — relanza Marcus para aplicar un cambio. Para un ajuste
  rápido, por-app y al instante, usa el zoom del texto (⌘+ / ⌘- / ⌘0):
  amplía el editor y la vista previa sobre el tamaño del sistema, sin tocar
  las demás apps.

## Filosofía

La velocidad es una funcionalidad. Nativo siempre. Sin bases de datos,
sin workspaces, sin sincronización, sin web views en la ruta de edición.
Tus archivos te pertenecen.
