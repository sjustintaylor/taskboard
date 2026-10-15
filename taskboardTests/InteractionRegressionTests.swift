import AppKit
import Testing
@testable import taskboard

private actor PendingRevision {
    private var continuation: CheckedContinuation<ProjectFile.Revision, any Error>?
    private var started: CheckedContinuation<Void, Never>?

    func read() async throws -> ProjectFile.Revision {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ result: Result<ProjectFile.Revision, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
struct InteractionRegressionTests {
    private func document() async throws -> KanbanDocument {
        let document = KanbanDocument()
        var project = Project()
        project.ungrouped = [BoardTask(id: "T-001", title: "Original")]
        try await document.apply(snapshot: ProjectSnapshot(project: project, baseline: project), previous: nil)
        return document
    }

    @Test(arguments: [false, true])
    func saveSupersedesPendingReload(failingRead: Bool) async throws {
        let document = try await document()
        let oldDisk = document.project
        let pending = PendingRevision()
        let reload = Task { await document.refresh { try await pending.read() } }
        await pending.waitUntilStarted()
        document.edit("Rename", undoManager: nil) { $0.title = "Saved title" }
        let written = document.project
        document.didSave(written: written, result: written)
        if failingRead {
            await pending.finish(.failure(BoardError("Obsolete read error")))
        } else {
            await pending.finish(.success(.init(project: oldDisk, modificationDate: .distantPast)))
        }
        await reload.value
        #expect(document.project == written)
        #expect(document.baseline == written)
        #expect(document.issue == nil)

        // A subsequent, genuinely newer external edit must still be loaded.
        var external = written
        external.update("T-001") { $0.title = "External title" }
        let current = external
        await document.refresh { .init(project: current, modificationDate: .now) }
        #expect(document.project == external)
    }

    @Test func newerReloadSupersedesOlderCompletion() async throws {
        let document = try await document()
        let oldDisk = document.project
        let pending = PendingRevision()
        let oldRead = Task { await document.refresh { try await pending.read() } }
        await pending.waitUntilStarted()
        var newer = oldDisk
        newer.title = "New external title"
        let newDisk = newer
        await document.refresh { .init(project: newDisk, modificationDate: .now) }
        await pending.finish(.success(.init(project: oldDisk, modificationDate: .distantPast)))
        await oldRead.value
        #expect(document.project == newDisk)
        #expect(document.baseline == newDisk)
    }

    @Test(arguments: [false, true])
    func nativeReaderSnapshotCannotUndoSave(diagnostic: Bool) async throws {
        let document = try await document()
        let oldDisk = document.project
        let context = document.beginRead()
        document.edit("Rename", undoManager: nil) { $0.title = "Saved title" }
        let written = document.project
        document.didSave(written: written, result: written)
        try await document.apply(snapshot: ProjectSnapshot(project: oldDisk, baseline: oldDisk,
            diagnostic: diagnostic ? "Obsolete parse error" : nil, readGeneration: context.generation), previous: nil)
        #expect(document.project == written)
        #expect(document.baseline == written)
        #expect(document.issue == nil)
    }

    @Test func foreignDropsCannotMoveMatchingTaskIDs() async throws {
        let source = try await document(), destination = try await document()
        let before = destination.project
        let foreign = TaskDragPayload(documentID: source.dragIdentity, taskID: "T-001")
        // Exercise the serialized payload used by drag-and-drop.
        let decoded = try JSONDecoder().decode(TaskDragPayload.self, from: JSONEncoder().encode(foreign))
        #expect(!destination.drop([decoded], status: .done, undoManager: nil))
        #expect(destination.project == before)
        let local = TaskDragPayload(documentID: destination.dragIdentity, taskID: "T-001")
        #expect(!destination.drop([local, decoded], status: .done, undoManager: nil))
        #expect(destination.project == before)
        #expect(destination.drop([local], status: .doing, undoManager: nil))
        #expect(destination.project.task("T-001")?.status == .doing)
        #expect(source.project == before)
    }

    @Test func sameDocumentDropRetainsOrderingAndUndo() async throws {
        let document = try await document()
        document.edit("Add task", undoManager: nil) { $0.ungrouped.append(BoardTask(id: "T-002")) }
        let before = document.project
        let manager = UndoManager()
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        let payload = TaskDragPayload(documentID: document.dragIdentity, taskID: "T-002")
        #expect(document.drop([payload], status: .todo, before: "T-001", undoManager: manager))
        manager.endUndoGrouping()
        #expect(document.project.tasks.map(\.id) == ["T-002", "T-001"])
        manager.undo()
        #expect(document.project == before)
    }

    @Test func navigationRequiresBoardFocus() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var navigations = 0, opens = 0, escapes = 0
        let coordinator = BoardKeyboardShortcuts(boardFocused: false,
            navigate: { _ in navigations += 1 }, navigateColumn: { _ in navigations += 1 },
            open: { opens += 1 }, escape: { escapes += 1 }).makeCoordinator()
        func event(_ key: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: key))
        }
        // Inspector controls own focus: navigation and activation must reach them.
        for key: UInt16 in [123, 124, 125, 126, 36] {
            let input = try event(key)
            #expect(coordinator.handle(input, in: window) === input)
        }
        #expect(navigations == 0)
        #expect(opens == 0)
        coordinator.actions.boardFocused = true
        for key: UInt16 in [123, 124, 125, 126, 36] {
            #expect(coordinator.handle(try event(key), in: window) == nil)
        }
        #expect(navigations == 4)
        #expect(opens == 1)
        let modified = try event(125, modifiers: .command)
        #expect(coordinator.handle(modified, in: window) === modified)

        // Text editing wins even before SwiftUI has propagated a focus change.
        let editor = NSTextView(frame: .zero)
        window.contentView?.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        let typing = try event(125)
        #expect(coordinator.handle(typing, in: window) === typing)
        #expect(navigations == 4)
        #expect(coordinator.handle(try event(53), in: window) == nil)
        #expect(escapes == 1)
    }
}
