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
Files are read as UTF-8 (UTF-16/32 with a byte-order mark, and legacy
encodings when the conversion is lossless) and always saved as UTF-8
without BOM; the file's own line endings (LF, CRLF or CR) are kept.
Binary data is refused rather than opened as garbage.
Autosave, versions and session restore work like in any native Mac app.

## Markdown, exemplified

### Emphasis

Text can be **bold**, *italic*, ~~struck through~~ or `inline code`.

### Superscript and subscript

The Format menu turns the selection into Unicode superscript or subscript
characters — `2` becomes `²` (⌃⌘=) or `₂` (⌃⌘-). With no selection it
works on the word around the caret, so with the caret inside `H2O`,
subscript gives `H₂O`. Run it again on already-converted text and it goes
back to normal.

These are ordinary characters, not markup: the file stays portable and
looks the same on GitHub or anywhere else. The catch is Unicode's own
limit — only characters that *have* a superscript or subscript form are
converted. Digits and the signs `+ - = ( )` are complete; letters only in
part (uppercase has almost no subscript, which is exactly why the `H` and
`O` in `H₂O` stay put). Anything without a form is left untouched.

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

To make one, select the text and paste the URL (⌘V): the selection
becomes `[text](url)` instead of being replaced. It only triggers on a
real URL (`https://…`, `mailto:…` and the like — not a bare `example.com`)
and only over a selection on one line; anything else pastes as usual, and
⌘Z undoes the link in one step.

---

That horizontal rule above is `---` on its own line.

### YAML front matter

When the **first line of the file** is exactly `---`, the block up to
the next `---` is treated as metadata (the "front matter" of Jekyll,
Hugo or Obsidian): the editor dims it and does not read it as Markdown,
and the preview, the exports, Copy as HTML and the word count leave it
out. Marcus does not validate the YAML — the block is yours. Without the
closing line
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
| ⌃⌘= / ⌃⌘- | Superscript / subscript on the selection (Unicode) |
| ⌘V over a selection | With a URL on the clipboard: makes the selection a link |
| ⌘+ (or ⌘=) / ⌘- | Zoom the editor and preview text in / out |
| ⌘: / ⌘; | Spelling panel / check document now |
| ⌘0 | Reset the text zoom to 100% |
| ⌘, | Settings |
| ⌘F | Find; ⌥⌘F find and replace |
| ⌘⇧H | This guide |

File → Export as PDF… writes the PDF directly, without the print dialog.
Like the preview, print and PDF never fetch anything from the network:
local images are embedded, remote ones are left out.

## Settings worth knowing

- **Preview**: side panel or full window (Settings, ⌘,). In the side
  panel, the preview follows the editor caret by section; in full-window
  mode, the title bar and a discreet eye icon at the top right say the
  editor is hidden.
- **Editor theme**: System, Sepia or Midnight — also under View → Theme.
  The preview follows the theme.
- **Appearance**: light / dark / system, under View → Appearance.
- **Check spelling while typing**: on by default — the system's red
  underline, in the language of the text; nothing is ever corrected
  behind your back (smart quotes and auto-correction stay off: they
  corrupt Markdown). Turn it off in Settings or under Edit → Spelling and
  Grammar, which also offers the spelling panel (⌘:) and Check Document
  Now (⌘;).
- **Spelling language**: "System" by default — usually macOS's "Automatic
  by Language", which guesses the language paragraph by paragraph and can
  mis-guess a short line full of symbols (a heading like
  `# idyoma & ortografia` reads as Hungarian and goes unmarked). Pick a
  fixed language in Settings and Marcus checks everything in it, without
  touching the system-wide setting or other apps.
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
- **Accessibility**: Marcus works with VoiceOver — the outline (each
  heading says its level), the count bar, the editor, the preview and
  the full-window indicator are all labeled, and showing or hiding the
  preview or the outline is announced. It also respects the system text
  size (System Settings → Accessibility → Display → Text size): the
  editor, the interface and the preview grow with it — relaunch Marcus to
  apply a change. For a quick, per-app adjustment that takes effect at
  once, use the text zoom (⌘+ / ⌘- / ⌘0): it scales the editor and preview
  on top of the system size, without touching other apps.

## Philosophy

Speed is a feature. Native always. No databases, no workspaces, no sync,
no web views on the editing path. Your files belong to you.
