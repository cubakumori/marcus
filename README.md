# Marcus

Editor de Markdown nativo para macOS. Extremadamente rápido, ligero y sin
ecosistema: abre, edita y guarda archivos `.md` de forma excelente. Nada más.

> La experiencia por defecto debe ser la mejor experiencia: instalar, abrir y
> empezar a escribir es suficiente.

## Estado

En desarrollo activo — **Fase 1 (editor)**. Consulta el estado detallado y las
decisiones técnicas en el [ROADMAP](ROADMAP.md); la visión y el manifiesto
están en [my.docs/Plan_de_Implementacion_Marcus.md](my.docs/Plan_de_Implementacion_Marcus.md).

Lo que ya funciona:

- App de documentos nativa (`NSDocument`): nuevo, abrir, guardar, autoguardado,
  versiones, Open Recent, pestañas nativas.
- Editor sobre TextKit 2 con resaltado de sintaxis Markdown incremental
  (solo se recalculan las líneas afectadas por cada edición).
- Buscar y reemplazar con la barra de búsqueda nativa.
- Deshacer/rehacer integrado con el estado del documento.
- UTF-8 con o sin BOM (con detección de fallback); modo claro/oscuro del sistema.

## Requisitos

- macOS 14 o superior.
- Para compilar: Xcode 26 / Swift 6 (solo toolchain de línea de comandos ya basta).

## Compilar y ejecutar

```sh
swift run            # compila y lanza Marcus
swift test           # ejecuta la batería de tests
swift build -c release   # binario optimizado en .build/release/Marcus
```

Para generar un `.app` distribuible, ver [DEPLOY.md](DEPLOY.md).

## Estructura

```
Sources/MarcusCore/   Lógica pura y testeable (escáner Markdown) — sin AppKit
Sources/Marcus/       La app: documento, editor, resaltador, menús
Tests/                Tests unitarios de MarcusCore
ROADMAP.md            Decisiones técnicas, presupuestos de rendimiento y fases
CHANGELOG.md          Historial de versiones
DEPLOY.md             Proceso de build de release y distribución
```

## Principios (resumen)

La velocidad es una característica. El archivo es la fuente de verdad. Nativo
siempre. Sin bases de datos, sin indexación permanente, sin workspaces
obligatorios, sin sincronización propia, sin web views en la ruta de edición.
Los archivos pertenecen al usuario.

## Licencia

Pendiente de decidir.
