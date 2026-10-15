import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Attach after SwiftUI finishes installing its native document/window controller.
struct DocumentWindowSetup: NSViewRepresentable {
    let document: KanbanDocument
    func makeNSView(context: Context) -> NSView {
        let view = NamingView(); view.owner = document; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class NamingView: NSView {
        weak var owner: KanbanDocument?
        private var attachment: Task<Void, Never>?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachment?.cancel()
            guard let window else { return }
            WelcomeController.shared?.documentOpened()
            attachment = Task { @MainActor [weak self, weak window] in
                for _ in 0..<20 {
                    guard !Task.isCancelled, let self, let window, self.window === window else { return }
                    if let document = NSDocumentController.shared.document(for: window) {
                        self.owner?.nativeDocument = document
                        if document.fileURL == nil {
                            document.fileType = UTType.kanbanProject.identifier
                            document.displayName = "Untitled.kanban"
                        }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }
}
