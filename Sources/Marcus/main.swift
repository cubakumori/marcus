import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate

// Ensure the shared document controller exists before the app finishes
// launching; it reads document types from the embedded Info.plist.
_ = NSDocumentController.shared

app.run()
