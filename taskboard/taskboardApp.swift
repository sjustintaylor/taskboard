import SwiftUI

@main
struct TaskboardApp: App {
    var body: some Scene {
        DocumentGroup { (document: KanbanDocument) in
            ContentView(document: document)
        } makeDocument: { configuration, _ in
            KanbanDocument(configuration: configuration)
        }
        .defaultSize(width: 1240, height: 800)
        .commands { TextEditingCommands() }
    }
}
