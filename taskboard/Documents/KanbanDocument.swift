import SwiftUI
import UniformTypeIdentifiers
import Observation

extension UTType {
    static let kanbanProject = UTType(exportedAs: "com.taskboard.kanban", conformingTo: .yaml)
}

struct KanbanReader: DocumentReader {
    var lastValid: @Sendable () async -> Project?
    @concurrent func read(from source: sending URL, progress: consuming Subprogress) async throws -> sending ProjectSnapshot {
        do {
            let project = try ProjectFile.read(source, alreadyCoordinated: true)
            return ProjectSnapshot(project: project, baseline: project)
        } catch {
            guard let project = await lastValid() else { throw error }
            return ProjectSnapshot(project: project, baseline: nil, diagnostic: error.localizedDescription)
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
    var issue: String?
    var editError: String?
    var conflict = false
    var externalProject: Project?
    @ObservationIgnored weak var nativeDocument: NSDocument?
    let configuration: URLDocumentConfiguration?
    var fileURL: URL? { configuration?.fileURL }

    init(configuration: URLDocumentConfiguration? = nil) { self.configuration = configuration }
    nonisolated func reader(configuration: sending DocumentReadConfiguration) -> sending KanbanReader {
        KanbanReader { [weak self] in await self?.baseline }
    }
    nonisolated func writer(configuration: sending DocumentWriteConfiguration) -> sending KanbanWriter {
        KanbanWriter { [weak self] written, result in await self?.didSave(written: written, result: result) }
    }
    private func didSave(written: Project, result: Project) {
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
        do {
            let coordinator = configuration?.makeFileCoordinator()
            let revision = try await Task.detached { try ProjectFile.readRevision(url, coordinator: coordinator) }.value
            acceptExternal(revision.project)
            if !conflict {
                // Acknowledge the precise disk revision to the native document system.
                // This is disk metadata, never a synthetic date for a UI edit.
                configuration?.lastContentModificationDate = revision.modificationDate
                if let nativeDocument, nativeDocument.fileModificationDate != revision.modificationDate {
                    nativeDocument.performAsynchronousFileAccess { done in
                        nativeDocument.fileModificationDate = revision.modificationDate
                        done()
                    }
                }
            }
        } catch {
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
                project = remote; baseline = remote; issue = nil; conflict = false; externalProject = nil
            }
        } catch { issue = error.localizedDescription }
    }
}
