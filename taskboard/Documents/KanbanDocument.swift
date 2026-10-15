import SwiftUI
import UniformTypeIdentifiers
import Observation

extension UTType {
    static let kanbanProject = UTType(exportedAs: "com.taskboard.kanban", conformingTo: .yaml)
}

struct KanbanReader: DocumentReader {
    struct Context: Sendable {
        var lastValid: Project?
        var generation: UInt64
    }
    var beginRead: @Sendable () async -> Context
    @concurrent func read(from source: sending URL, progress: consuming Subprogress) async throws -> sending ProjectSnapshot {
        let context = await beginRead()
        do {
            let project = try ProjectFile.read(source, alreadyCoordinated: true)
            return ProjectSnapshot(project: project, baseline: project, readGeneration: context.generation)
        } catch {
            guard let project = context.lastValid else { throw error }
            return ProjectSnapshot(project: project, baseline: nil, diagnostic: error.localizedDescription, readGeneration: context.generation)
        }
    }
}

struct KanbanWriter: DocumentWriter {
    var saved: @Sendable (Project, Project) async -> Void
    @concurrent func write(snapshot: sending ProjectSnapshot, to destination: sending URL, previous: sending ProjectSnapshot?, progress: consuming Subprogress) async throws {
        let result = try ProjectFile.save(snapshot, to: destination, alreadyCoordinated: true)
        await saved(snapshot.project, result)
    }
}

@MainActor @Observable final class KanbanDocument: Document {
    nonisolated static var readableContentTypes: [UTType] { [.kanbanProject, .yaml] }
    var project = Project()
    @ObservationIgnored var baseline: Project?
    @ObservationIgnored private var readGeneration: UInt64 = 0
    let dragIdentity = UUID()
    var issue: String?
    var editError: String?
    var conflict = false
    var externalProject: Project?
    @ObservationIgnored weak var nativeDocument: NSDocument?
    let configuration: URLDocumentConfiguration?
    var fileURL: URL? { configuration?.fileURL }

    init(configuration: URLDocumentConfiguration? = nil) { self.configuration = configuration }
    nonisolated func reader(configuration: sending DocumentReadConfiguration) -> sending KanbanReader {
        KanbanReader { await self.beginRead() }
    }
    nonisolated func writer(configuration: sending DocumentWriteConfiguration) -> sending KanbanWriter {
        KanbanWriter { [weak self] written, result in await self?.didSave(written: written, result: result) }
    }
    func beginRead() -> KanbanReader.Context {
        // Only the latest read may apply; saves and recovery invalidate in-flight reads too.
        readGeneration &+= 1
        return KanbanReader.Context(lastValid: baseline, generation: readGeneration)
    }
    func didSave(written: Project, result: Project) {
        readGeneration &+= 1
        do {
            project = try ProjectMerge.merge(base: written, local: project, remote: result)
            baseline = result
        } catch { issue = error.localizedDescription; conflict = true; externalProject = result }
    }

    func snapshot(contentType: UTType) async throws -> sending ProjectSnapshot {
        guard issue == nil else { throw BoardError(issue!) }
        return ProjectSnapshot(project: project, baseline: baseline, sourceURL: fileURL)
    }
    func apply(snapshot: sending ProjectSnapshot, previous: sending ProjectSnapshot?) async throws {
        if let generation = snapshot.readGeneration, generation != readGeneration { return }
        readGeneration &+= 1
        if let diagnostic = snapshot.diagnostic {
            issue = "External YAML is invalid: \(diagnostic)\nThe last valid board is retained. Saving is paused until the file is repaired."
            conflict = false; externalProject = nil
            return
        }
        acceptExternal(snapshot.project)
    }
    private func acceptExternal(_ remote: Project) {
        if remote == baseline && issue == nil { return }
        do {
            let merged = try baseline.map { try ProjectMerge.merge(base: $0, local: project, remote: remote) } ?? remote
            if project != merged { project = merged }
            baseline = remote; issue = nil; conflict = false; externalProject = nil
        } catch {
            issue = error.localizedDescription; conflict = true; externalProject = remote
        }
    }
    func refresh() async {
        guard let url = fileURL else { return }
        await refresh {
            let coordinator = configuration?.makeFileCoordinator()
            return try await Task.detached { try ProjectFile.readRevision(url, coordinator: coordinator) }.value
        }
    }
    func refresh(readRevision: () async throws -> ProjectFile.Revision) async {
        let generation = beginRead().generation
        do {
            let revision = try await readRevision()
            guard generation == readGeneration else { return }
            acceptExternal(revision.project)
            if !conflict {
                // Acknowledge the precise disk revision to the native document system.
                // This is disk metadata, never a synthetic date for a UI edit.
                configuration?.lastContentModificationDate = revision.modificationDate
                if let nativeDocument, nativeDocument.fileModificationDate != revision.modificationDate {
                    nativeDocument.performAsynchronousFileAccess { done in
                        if generation == self.readGeneration {
                            nativeDocument.fileModificationDate = revision.modificationDate
                        }
                        done()
                    }
                }
            }
        } catch {
            guard generation == readGeneration else { return }
            issue = "External file cannot be loaded: \(error.localizedDescription)\nThe last valid board is retained. Saving is paused until the file is repaired."
            conflict = false; externalProject = nil
        }
    }
    func edit(_ name: String, undoManager: UndoManager?, _ change: (inout Project) -> Void) {
        guard issue == nil else { return }
        var updated = project
        change(&updated)
        guard updated != project else { return }
        do { _ = try YAMLCodec.encode(updated) }
        catch { editError = error.localizedDescription; return }
        replace(updated, name: name, undoManager: undoManager)
    }
    @discardableResult
    func drop(_ payloads: [TaskDragPayload], status: TaskStatus, group: String? = nil,
              changeGroup: Bool = false, before: String? = nil, undoManager: UndoManager?) -> Bool {
        guard issue == nil, !payloads.isEmpty,
              payloads.allSatisfy({ $0.documentID == dragIdentity && project.task($0.taskID) != nil }) else { return false }
        let ids = Set(payloads.map(\.taskID))
        edit("Move Tasks", undoManager: undoManager) {
            $0.move(ids, status: status, group: group, changeGroup: changeGroup, before: before)
        }
        return true
    }
    private func replace(_ updated: Project, name: String, undoManager: UndoManager?) {
        let old = project
        // Undo only the fields changed by this edit, preserving subsequent external work.
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] target in
            do {
                let reverted = try ProjectMerge.merge(base: updated, local: old, remote: target.project)
                target.replace(reverted, name: name, undoManager: undoManager)
            } catch { target.editError = "Undo conflicts with newer changes: \(error.localizedDescription)" }
        }
        undoManager?.setActionName(name)
        project = updated
    }

    /// Export first, then accept disk; neither version is silently discarded.
    func exportLocalAndReload() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Local Changes.kanban.yaml"
        panel.allowedContentTypes = [.yaml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard url.standardizedFileURL != fileURL?.standardizedFileURL else { throw BoardError("Choose a different path to preserve the external version.") }
            try YAMLCodec.encode(project).write(to: url, options: .atomic)
            if let remote = externalProject {
                readGeneration &+= 1
                project = remote; baseline = remote; issue = nil; conflict = false; externalProject = nil
            }
        } catch { issue = error.localizedDescription }
    }
}
