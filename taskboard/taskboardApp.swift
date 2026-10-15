import SwiftUI

@main
struct TaskboardApp: App {
    @NSApplicationDelegateAdaptor private var delegate: WelcomeController
    var body: some Scene {
        DocumentGroup { (document: KanbanDocument) in
            ContentView(document: document)
        } makeDocument: { configuration, _ in
            KanbanDocument(configuration: configuration)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1240, height: 800)
        .commands {
            TextEditingCommands()
            CommandGroup(after: .windowArrangement) {
                Button("Welcome to Taskboard") { WelcomeController.shared.show() }
            }
        }
    }
}
