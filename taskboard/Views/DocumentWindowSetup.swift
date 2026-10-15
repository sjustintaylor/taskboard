import SwiftUI
import AppKit

/// Keep the standard YAML extension while suggesting the compound project filename.
struct DocumentWindowSetup: NSViewRepresentable {
    let document: KanbanDocument
    func makeNSView(context: Context) -> NSView {
        let view = NamingView(); view.owner = document; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class NamingView: NSView {
        weak var owner: KanbanDocument?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async {
                if let document = NSDocumentController.shared.document(for: window) {
                    self.owner?.nativeDocument = document
                    if document.fileURL == nil { document.displayName = "Untitled.kanban" }
                }
            }
        }
    }
}
