# Marcus Guide

Welcome. This document is both the manual and a live demo: press ⌘⇧P to
see it rendered side by side, and ⌘⇧O to browse it from the outline.
It opens read-only — your own files are never touched.

## The essentials

Marcus is a primary tool for text, optimized for Markdown. It opens,
edits and saves plain Markdown files (`.md`) and plain text (`.txt`) —
and, if you enable "Open any text file" in Settings, any other text
format (HTML, CSS, logs, config files…) *as text*: no highlighting, no
preview, no pretending. The type follows the file — a `.txt` stays
`.txt` when saved —, new documents are Markdown, and the save panel
lets you pick the format. The word-count bar and, for non-Markdown
files, the window subtitle always say what you are editing. Nothing is
imported, indexed or converted: the file on disk is the only truth.
Autosave, versions and session restore work like in any native Mac app.

## Markdown, exemplified

### Emphasis

Text can be **bold**, *italic*, ~~struck through~~ or `inline code`.

### Lists

1. Ordered item
2. Another one
   - nested bullet

- [x] A done task
- [ ] A pending task

### Quotes and code

> A quote spans
> as many lines as it needs.

```swift
let answer = 42  // fenced code, with language
```

### Tables and links

| Column | Aligned |
|:-------|--------:|
| left   |   right |

A [link](https://example.com) opens with ⌘-click — a plain click edits
it, as it should in an editor. Relative links and images resolve against
the document's folder.

---

That horizontal rule above is `---` on its own line.

### YAML front matter

When the **first line of the file** is exactly `---`, the block up to
the next `---` is treated as metadata (the "front matter" of Jekyll,
Hugo or Obsidian): the editor dims it and does not read it as Markdown,
and the preview, the exports and Copy as HTML leave it out. Marcus does
not validate the YAML — the block is yours. Without the closing line
there is no block: a document that opens with a horizontal rule is
still plain Markdown.

## Keyboard shortcuts

| Shortcut | Action |
|:---------|:-------|
| ⌘⇧P | Show / hide the preview |
| ⌘⇧O | Show / hide the outline |
| ⌘⇧E | Export as HTML (single self-contained file) |
| ⌥⌘C | Copy the selection (or the whole document) as HTML |
| ⌘P | Print, or save as paginated PDF |
| ⌘B / ⌘I | Bold / italic on the selection |
| ⌘, | Settings |
| ⌘F | Find; ⌥⌘F find and replace |
| ⌘⇧H | This guide |

File → Export as PDF… writes the PDF directly, without the print dialog.

## Settings worth knowing

- **Preview**: side panel or full window (Settings, ⌘,). In the side
  panel, the preview follows the editor caret by section; in full-window
  mode, the title bar and a discreet eye icon at the top right say the
  editor is hidden.
- **Editor theme**: System, Sepia or Midnight — also under View → Theme.
  The preview follows the theme.
- **Appearance**: light / dark / system, under View → Appearance.
- **Continue lists on ⏎**: off by default; enable it in Settings and
  Return will keep your lists going (an empty item ends the list).
- **Open documents in tabs**: off by default; enable it in Settings and
  documents open as tabs of one window instead of separate windows.
- **Open any text file**: off by default; enable it in Settings and the
  open panel accepts any text format — edited as honest plain text,
  saved back as whatever it already was. Formats that are never text
  (images, audio, archives…) are still refused.
- **Word count**: View → Show Word Count. The bar also names the
  document's format.

## Make it yours (system features)

- **Language**: Marcus follows the system language (English/Spanish). To
  change it only for Marcus: System Settings → General → Language &
  Region → Applications → “+”.
- **Custom shortcuts**: System Settings → Keyboard → Keyboard Shortcuts →
  App Shortcuts lets you rebind any menu item by its exact title.

## Philosophy

Speed is a feature. Native always. No databases, no workspaces, no sync,
no web views on the editing path. Your files belong to you.
