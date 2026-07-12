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
El autoguardado, las versiones y la restauración de sesión funcionan
como en cualquier app nativa del Mac.

## Markdown, con ejemplos

### Énfasis

El texto puede ir en **negrita**, *cursiva*, ~~tachado~~ o `código en
línea`.

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
| ⌘, | Ajustes |
| ⌘F | Buscar; ⌥⌘F buscar y reemplazar |
| ⌘⇧H | Esta guía |

Archivo → Exportar como PDF… escribe el PDF directamente, sin pasar por
el diálogo de impresión.

## Ajustes que conviene conocer

- **Vista previa**: panel lateral o ventana completa (Ajustes, ⌘,). En
  panel, la vista previa sigue al cursor del editor por secciones; en
  ventana completa, la barra de título y un ojo discreto arriba a la
  derecha indican que el editor está oculto.
- **Tema del editor**: Sistema, Sepia o Medianoche — también en
  Visualización → Tema. La vista previa sigue el tema.
- **Apariencia**: claro / oscuro / sistema, en Visualización → Apariencia.
- **Continuar listas al pulsar ⏎**: desactivado por defecto; actívalo en
  Ajustes y ⏎ continuará tus listas (un elemento vacío cierra la lista).
- **Abrir documentos en pestañas**: desactivado por defecto; actívalo en
  Ajustes y los documentos se abrirán como pestañas de una única ventana
  en vez de ventanas sueltas.
- **Abrir cualquier archivo de texto**: desactivado por defecto;
  actívalo en Ajustes y el panel de abrir admitirá cualquier formato de
  texto — editado como texto plano honesto y guardado como lo que ya
  era. Los formatos que nunca son texto (imágenes, audio, archivos
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
  crecen con él — relanza Marcus para aplicar un cambio.

## Filosofía

La velocidad es una funcionalidad. Nativo siempre. Sin bases de datos,
sin workspaces, sin sincronización, sin web views en la ruta de edición.
Tus archivos te pertenecen.
