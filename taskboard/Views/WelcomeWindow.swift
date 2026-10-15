import SwiftUI
import AppKit

@MainActor final class WelcomeController: NSObject, NSApplicationDelegate {
    static var shared: WelcomeController!
    override init() { super.init(); Self.shared = self }
    private var welcome: NSWindow?
    private var observers: [NSObjectProtocol] = []
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow,
                      NSDocumentController.shared.document(for: window) != nil else { return }
                DispatchQueue.main.async { self?.showIfNeeded() }
            }
        })
        DispatchQueue.main.async { self.showIfNeeded() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showIfNeeded() }
        return true
    }
    func showIfNeeded() {
        if NSDocumentController.shared.documents.isEmpty { show() }
    }
    func documentOpened() { welcome?.orderOut(nil) }
    func show() {
        if welcome == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 460), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Welcome to Taskboard"
            window.isReleasedWhenClosed = false
            window.center()
            welcome = window
        }
        welcome?.contentView = NSHostingView(rootView: WelcomeView())
        welcome?.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    @State private var recent = NSDocumentController.shared.recentDocumentURLs
    @State private var error: String?
    @State private var failedURL: URL?
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: "rectangle.split.3x1").font(.system(size: 52)).foregroundStyle(.tint)
                Text("Taskboard").font(.largeTitle.bold())
                Button("New Board") { NSDocumentController.shared.newDocument(nil) }
                Button("Open Board…") { NSDocumentController.shared.openDocument(nil) }
            }.frame(width: 250, height: 460)
            Divider()
            VStack(alignment: .leading) {
                Text("Recent Boards").font(.headline).padding(.bottom, 8)
                if recent.isEmpty { ContentUnavailableView("No recent boards", systemImage: "doc", description: Text("Create a board or open an existing .kanban.yaml file.")) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(recent, id: \.self) { url in
                            Button { open(url) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.lastPathComponent).fontWeight(.medium)
                                    Text(url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Open \(url.lastPathComponent), \(url.path)")
                            Divider()
                        }
                    }
                }
            }.padding(20)
        }
        .alert("Board could not be opened", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
            Button("Remove from Recents") {
                if let failedURL {
                    let retained = NSDocumentController.shared.recentDocumentURLs.filter { $0 != failedURL }
                    NSDocumentController.shared.clearRecentDocuments(nil)
                    for url in retained.reversed() { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
                    recent = retained
                }
                error = nil
            }
        } message: { Text(error ?? "") }
    }
    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, failure in
            if let failure { error = failure.localizedDescription; failedURL = url }
            else { WelcomeController.shared.documentOpened() }
        }
    }
}
