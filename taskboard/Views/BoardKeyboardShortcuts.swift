import SwiftUI
import AppKit

/// Board navigation must also work when no text editor is first responder.
/// A window-scoped monitor leaves typing, native dialogs and menu shortcuts alone.
struct BoardKeyboardShortcuts: NSViewRepresentable {
    var navigate: (Int) -> Void
    var navigateColumn: (Int) -> Void
    var open: () -> Void
    var escape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(actions: self) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(view: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.actions = self }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    final class Coordinator {
        var actions: BoardKeyboardShortcuts
        private var monitor: Any?
        init(actions: BoardKeyboardShortcuts) { self.actions = actions }
        func install(view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let window = view?.window, event.window == window,
                      window.attachedSheet == nil,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                if event.keyCode == 53 { self.actions.escape(); return nil }
                guard !(window.firstResponder is NSTextView) else { return event }
                switch event.keyCode {
                case 126: self.actions.navigate(-1)
                case 125: self.actions.navigate(1)
                case 123: self.actions.navigateColumn(-1)
                case 124: self.actions.navigateColumn(1)
                case 36: self.actions.open()
                default: return event
                }
                return nil
            }
        }
        func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
