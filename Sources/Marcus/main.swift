import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate

// Ensure the shared document controller exists before the app finishes
// launching; it reads document types from the embedded Info.plist. Ours:
// the first NSDocumentController instantiated becomes the shared one, and
// it widens the open paths when "Open any text file" is on (Fase 6).
_ = MarcusDocumentController()

app.run()
