# Guía de Marcus

Bienvenido. Este documento es a la vez el manual y una demo en vivo:
pulsa ⌘⇧P para verlo renderizado al lado, y ⌘⇧O para navegarlo desde el
esquema. Se abre en solo lectura — tus archivos nunca se tocan.

## Lo esencial

Marcus abre, edita y guarda archivos Markdown planos (`.md`) y texto
plano (`.txt`). El tipo sigue al archivo — un `.txt` se guarda como
`.txt` —, los documentos nuevos son Markdown y el panel de guardado
permite elegir el formato. Nada se importa, indexa ni convierte: el
archivo en disco es la única verdad.
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

## Atajos de teclado

| Atajo | Acción |
|:------|:-------|
| ⌘⇧P | Mostrar / ocultar la vista previa |
| ⌘⇧O | Mostrar / ocultar el esquema |
| ⌘⇧E | Exportar como HTML (un único archivo autocontenido) |
| ⌘P | Imprimir, o guardar como PDF paginado |
| ⌘B / ⌘I | Negrita / cursiva sobre la selección |
| ⌘, | Ajustes |
| ⌘F | Buscar; ⌥⌘F buscar y reemplazar |
| ⌘⇧H | Esta guía |

Archivo → Exportar como PDF… escribe el PDF directamente, sin pasar por
el diálogo de impresión.

## Ajustes que conviene conocer

- **Vista previa**: panel lateral o ventana completa (Ajustes, ⌘,).
- **Tema del editor**: Sistema, Sepia o Medianoche — también en
  Visualización → Tema. La vista previa sigue el tema.
- **Apariencia**: claro / oscuro / sistema, en Visualización → Apariencia.
- **Continuar listas al pulsar ⏎**: desactivado por defecto; actívalo en
  Ajustes y ⏎ continuará tus listas (un elemento vacío cierra la lista).
- **Recuento de palabras**: Visualización → Mostrar recuento de palabras.

## Hazlo tuyo (funciones del sistema)

- **Idioma**: Marcus sigue el idioma del sistema (inglés/español). Para
  cambiarlo solo en Marcus: Ajustes del Sistema → General → Idioma y
  región → Aplicaciones → «+».
- **Atajos personalizados**: Ajustes del Sistema → Teclado → Funciones
  rápidas de teclado → Atajos de app permite redefinir cualquier
  elemento de menú por su título exacto.

## Filosofía

La velocidad es una funcionalidad. Nativo siempre. Sin bases de datos,
sin workspaces, sin sincronización, sin web views en la ruta de edición.
Tus archivos te pertenecen.
