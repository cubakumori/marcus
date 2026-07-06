<img src="Resources/marcus.png" alt="Marcus logo" width="128" align="right">

# Marcus

A native Markdown editor for macOS. Extremely fast, lightweight, and
ecosystem-free: it opens, edits, and saves `.md` files exceptionally well.
Nothing else.

> The default experience must be the best experience: install, open, and
> start writing.

## Status

Under active development — **Phase 4 (versatility) is complete** and ships
as v0.4.0: plain-text files, opt-in tabbed opening, and Copy as HTML. See the
[ROADMAP](ROADMAP.md) for detailed status and technical decisions; the vision
and manifesto live in
[my.docs/Plan_de_Implementacion_Marcus.md](my.docs/Plan_de_Implementacion_Marcus.md)
(Spanish).

What already works:

- Native document app (`NSDocument`): new, open, save, autosave, versions,
  Open Recent, native tabs, session restoration.
- Plain text: opens and saves `.txt` alongside `.md`. The type follows the
  file — no content sniffing —, new documents are Markdown, and the save
  panel's format popup is the confirmation. Optional "Open documents in
  tabs" setting groups openings into one window.
- TextKit 2 editor with truly incremental Markdown syntax highlighting
  (~4 ms per keystroke in a 10 MB document — only affected lines are
  re-scanned and re-styled).
- Native preview (⌘⇧P): reading typography rendered with
  `swift-markdown` + TextKit — no web views. Parsing runs in the background;
  editing never waits. Side-panel or full-window mode (Settings, ⌘,), and it
  follows the editor theme.
- Document outline (⌘⇧O): heading index in a sidebar, derived from the
  highlighter's scan — click to jump. In memory, per document; nothing is
  indexed or stored.
- Writing aids: opt-in list continuation on Return (bullets, numbered,
  tasks), and ⌘B / ⌘I to toggle emphasis on the selection.
- Word/character count (View menu) and ⌘-click to open links.
- Built-in bilingual guide (Help → Marcus Guide, ⌘⇧H): manual and live
  Markdown demo in one read-only document.
- Export as HTML (⌘⇧E): a single self-contained file — embedded CSS with
  light/dark support, local images inlined as data URIs, no scripts. Copy
  as HTML (⌥⌘C) puts the selection — or the whole document — on the
  clipboard for formatted pasting into mail, forums or blogs.
- Export as PDF and Print (⌘P): paginated output laid out by an on-demand
  `WKWebView` used purely as a layout engine (JavaScript disabled, never on
  the editing path).
- Localized UI — English and Spanish — following the system language. To use
  a different language just for Marcus: System Settings → General →
  Language & Region → Applications → "+" → choose Marcus and the language.
- Editor themes: System (follows appearance), Sepia, and Midnight
  (Settings, ⌘,).
- Find & replace with the native find bar; undo/redo tied to document state.
- External-change detection: silent reload when there are no unsaved edits,
  a clear choice when there are.
- UTF-8 with or without BOM (plus encoding-detection fallback);
  light/dark mode following the system, with a manual override.

## Requirements

- macOS 14 or later.
- To build: Xcode 26 / Swift 6 (the command-line toolchain is enough).

## Build and run

```sh
swift run                # build and launch Marcus
swift test               # run the test suite
swift test -c release    # includes the performance-budget tests
```

To produce a distributable `Marcus.app` and `.dmg`, see [DEPLOY.md](DEPLOY.md):

```sh
scripts/build-dmg.sh
```

## Project layout

```
Sources/MarcusCore/      Pure, testable logic (Markdown scanner) — no AppKit
Sources/MarcusPreview/   Preview renderer (swift-markdown AST → NSAttributedString)
Sources/Marcus/          The app: document, editor, highlighter, preview, menus
Tests/                   Unit, property, and performance tests
ROADMAP.md               Technical decisions, performance budgets, phases
CHANGELOG.md             Version history
DEPLOY.md                Release build and distribution process
```

## Principles (summary)

Speed is a feature. The file is the source of truth. Native always. No
databases, no permanent indexing, no mandatory workspaces, no built-in sync,
no web views on the editing path. Your files belong to you.

---

## Support this project

If you've found this **Marcus** app useful, please consider supporting me:

[![PayPal](https://img.shields.io/badge/PayPal-Donar-blue?style=for-the-badge&logo=paypal)](https://paypal.me/ernestortiz)

[![Ko-fi](https://img.shields.io/badge/BUY_ME_A-KO_FI-darkseagreen?style=for-the-badge&logo=ko-fi)](https://ko-fi.com/kumoricuba)

---

## License

[GNU Affero General Public License v3.0 or later](LICENSE)
(`AGPL-3.0-or-later`).
