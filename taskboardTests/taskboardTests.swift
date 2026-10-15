import Foundation
import Testing
@testable import taskboard

struct TaskboardTests {
    static let example = """
    format_version: 1
    project:
      title: Notes Application
      description: |-
        A lightweight native macOS notes application.
    groups:
      - id: foundation
        title: Foundation
        tasks:
          - id: T-001
            title: Create application skeleton
            status: done
            agent_notes: |-
              Created SwiftUI application.
          - id: T-002
            title: Implement persistence
            status: doing
            depends_on: [T-001]
            ready_for_review: true
            verification: ['Unit tests: passed']
      - id: interface
        title: User Interface
        tasks:
          - id: T-003
            title: Implement notes list
            status: todo
            depends_on: [T-002]
    ungrouped: []
    """
    func fixture() throws -> Project { try YAMLCodec.decode(Data(Self.example.utf8)) }
    func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Project.kanban.yaml")
    }
    @Test func roundTripIsStableAndRetainsExtensions() throws {
        var project = try fixture()
        project.extra["extension"] = .object(["labels": .array([.string("release"), .string("2026-01-02")])])
        project.metadata["owner"] = .string("Local developer")
        project.update("T-002") { $0.fields["custom"] = .integer(42); $0.fields["description"] = .string("first line\n  code()\nlast line\n") }
        let data = try YAMLCodec.encode(project)
        let decoded = try YAMLCodec.decode(data)
        #expect(decoded == project)
        #expect(try YAMLCodec.encode(decoded) == data)
        #expect(String(decoding: data, as: UTF8.self).contains("description: |"))
    }
    @Test func emptyProjectRoundTrip() throws {
        let p = Project()
        #expect(try YAMLCodec.decode(YAMLCodec.encode(p)) == p)
    }
    @Test(arguments: [
        ("format_version: 1", "format_version: 2"),
        ("status: doing", "status: pending"),
        ("id: T-003", "id: T-001"),
        ("id: interface", "id: foundation"),
        ("depends_on: [T-002]", "depends_on: [missing]"),
        ("depends_on: [T-002]", "depends_on: [T-003]"),
        ("title: Notes Application", "title: 123"),
        ("title: Notes Application", "title: 2026-01-02"),
        ("title: Notes Application", "title: !custom hello"),
        ("title: Notes Application", "title: &name hello"),
        ("title: Notes Application", "title: &name hello\n  description: *name"),
        ("title: Notes Application", "title: hello\n  title: duplicate"),
        ("ready_for_review: true", "ready_for_review: yes"),
        ("ready_for_review: true", "ready_for_review: 'true'"),
        ("ungrouped: []", "ungrouped: {}"),
        ("ungrouped: []", "ungrouped: null"),
        ("verification: ['Unit tests: passed']", "verification: [12]")
    ]) func invalidDocumentsAreRejected(replacement: (String, String)) throws {
        let source = Self.example.replacingOccurrences(of: replacement.0, with: replacement.1)
        #expect(throws: (any Error).self) { try YAMLCodec.decode(Data(source.utf8)) }
    }
    @Test func dependencyCyclesAcrossTasksRejected() throws {
        var p = try fixture()
        p.update("T-001") { $0.fields["depends_on"] = .array([.string("T-003")]) }
        #expect(throws: BoardError.self) { try YAMLCodec.encode(p) }
    }
    @Test func malformedAndMultipleDocumentsRejected() throws {
        for source in ["groups: [", Self.example + "\n---\n" + Self.example, ""] {
            #expect(throws: (any Error).self) { try YAMLCodec.decode(Data(source.utf8)) }
        }
    }
    @Test func movementPreservesIdentityMetadataAndReviewRules() throws {
        var p = try fixture()
        p.move(["T-002"], status: .done)
        #expect(p.groupID(for: "T-002") == "foundation")
        #expect(p.task("T-002")?.readyForReview == false)
        #expect(p.task("T-002")?.list("verification") == ["Unit tests: passed"])
        #expect(p.nextTask?.id == "T-003")
        #expect(p.groups[0].progress == 1)
        p.move(["T-001", "T-002"], group: "interface", changeGroup: true, before: "T-003")
        #expect(p.groups[1].tasks.map(\.id) == ["T-001", "T-002", "T-003"])
        p.deleteGroup("interface")
        #expect(p.ungrouped.count == 3)
        #expect(p.completed == 2)
        #expect(try YAMLCodec.decode(YAMLCodec.encode(p)) == p)
    }
    @Test func taskAndGroupOrderingPersists() throws {
        var p = try fixture()
        p.move(["T-002"], before: "T-001")
        p.reorderGroup("interface", offset: -1)
        let decoded = try YAMLCodec.decode(YAMLCodec.encode(p))
        #expect(decoded.groups.map(\.id) == ["interface", "foundation"])
        #expect(decoded.groups[1].tasks.map(\.id) == ["T-002", "T-001"])
    }
    @Test func deleteTaskRemovesDanglingDependencies() throws {
        var p = try fixture(); p.delete(["T-002"])
        #expect(p.task("T-003")?.list("depends_on").isEmpty == true)
        #expect(try YAMLCodec.decode(YAMLCodec.encode(p)) == p)
    }
    @Test func nextBriefFollowsGroupOrderAndEligibility() throws {
        var p = try fixture()
        #expect(p.nextTask == nil)
        p.update("T-002") { $0.status = .done }
        let task = try #require(p.nextTask)
        let brief = AgentBrief.make(task: task, project: p, fileURL: URL(fileURLWithPath: "/tmp/notes.kanban.yaml"))
        for required in ["T-003", "Notes Application", "/tmp/notes.kanban.yaml", "T-002", "ready_for_review: true", "status: doing", "verification", "Preserve all IDs"] { #expect(brief.contains(required)) }
    }
    @Test func mergeIndependentTaskAndFieldChanges() throws {
        let base = try fixture(); var local = base, remote = base
        local.update("T-002") { $0.title = "Local title" }
        remote.update("T-002") { $0.fields["agent_notes"] = .string("Agent finished") }
        remote.update("T-003") { $0.title = "Agent title" }
        let merged = try ProjectMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.task("T-002")?.title == "Local title")
        #expect(merged.task("T-002")?.text("agent_notes") == "Agent finished")
        #expect(merged.task("T-003")?.title == "Agent title")
    }
    @Test func mergeReorderWithIndependentEdit() throws {
        let base = try fixture(); var local = base, remote = base
        local.move(["T-002"], before: "T-001")
        remote.update("T-002") { $0.title = "External title" }
        let merged = try ProjectMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.groups[0].tasks.map(\.id) == ["T-002", "T-001"])
        #expect(merged.task("T-002")?.title == "External title")
    }
    @Test func conflictsDoNotDiscardEitherVersion() throws {
        let base = try fixture(); var local = base, remote = base
        local.update("T-002") { $0.title = "Local" }
        remote.update("T-002") { $0.title = "Remote" }
        #expect(throws: BoardError.self) { try ProjectMerge.merge(base: base, local: local, remote: remote) }
        remote = base; remote.delete(["T-002"])
        #expect(throws: BoardError.self) { try ProjectMerge.merge(base: base, local: local, remote: remote) }
    }
    @Test func savesMergeAndUnchangedFilesKeepOriginalBytes() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = Data(("# Preserve this comment\n" + Self.example + "\n").utf8)
        try original.write(to: url)
        let base = try ProjectFile.read(url)
        let oldDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try ProjectFile.save(ProjectSnapshot(project: base, baseline: base), to: url)
        #expect(try Data(contentsOf: url) == original)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == oldDate)
        var local = base, remote = base
        local.update("T-003") { $0.title = "Local" }
        remote.update("T-002") { $0.fields["agent_notes"] = .string("External") }
        try YAMLCodec.encode(remote).write(to: url, options: .atomic)
        let result = try ProjectFile.save(ProjectSnapshot(project: local, baseline: base), to: url)
        #expect(result.task("T-003")?.title == "Local")
        #expect(result.task("T-002")?.text("agent_notes") == "External")
        #expect(try ProjectFile.read(url) == result)
    }
    @Test func invalidExternalFileAndConflictCannotBeOverwritten() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let base = try fixture(); var local = base
        local.update("T-002") { $0.title = "Local" }
        let invalid = Data("project: [broken".utf8); try invalid.write(to: url)
        #expect(throws: (any Error).self) { try ProjectFile.save(ProjectSnapshot(project: local, baseline: base), to: url) }
        #expect(try Data(contentsOf: url) == invalid)
        var remote = base; remote.update("T-002") { $0.title = "Remote" }
        let bytes = try YAMLCodec.encode(remote); try bytes.write(to: url, options: .atomic)
        #expect(throws: BoardError.self) { try ProjectFile.save(ProjectSnapshot(project: local, baseline: base), to: url) }
        #expect(try Data(contentsOf: url) == bytes)
    }
    @Test func removedFileRequiresRecoveryCopy() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let p = try fixture()
        #expect(throws: BoardError.self) { try ProjectFile.save(ProjectSnapshot(project: p, baseline: p), to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try ProjectFile.save(ProjectSnapshot(project: p, baseline: nil), to: url)
        #expect(try ProjectFile.read(url) == p)
    }
    @MainActor @Test func undoRedoAndExternalReload() async throws {
        let document = KanbanDocument(), manager = UndoManager()
        manager.groupsByEvent = false
        let base = try fixture()
        try await document.apply(snapshot: ProjectSnapshot(project: base, baseline: base), previous: nil)
        manager.beginUndoGrouping()
        document.edit("Rename", undoManager: manager) { $0.update("T-003") { $0.title = "Local title" } }
        manager.endUndoGrouping()
        var remote = base; remote.update("T-002") { $0.fields["agent_notes"] = .string("Agent notes") }
        try await document.apply(snapshot: ProjectSnapshot(project: remote, baseline: remote), previous: nil)
        manager.undo()
        #expect(document.project.task("T-003")?.title == "Implement notes list")
        #expect(document.project.task("T-002")?.text("agent_notes") == "Agent notes")
        manager.redo()
        #expect(document.project.task("T-003")?.title == "Local title")
    }
    @MainActor @Test func documentRetainsLocalAndRemoteOnConflict() async throws {
        let document = KanbanDocument(); let base = try fixture()
        try await document.apply(snapshot: ProjectSnapshot(project: base, baseline: base), previous: nil)
        document.edit("Rename", undoManager: nil) { $0.update("T-003") { $0.title = "Local" } }
        var remote = base; remote.update("T-003") { $0.title = "Remote" }
        try await document.apply(snapshot: ProjectSnapshot(project: remote, baseline: remote), previous: nil)
        #expect(document.conflict)
        #expect(document.project.task("T-003")?.title == "Local")
        #expect(document.externalProject?.task("T-003")?.title == "Remote")
    }
    @Test func nativeStagingSaveComparesAgainstAuthoritativeSource() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let staging = url.deletingLastPathComponent().appendingPathComponent("staging.yaml")
        let base = try fixture(); try YAMLCodec.encode(base).write(to: url)
        var local = base, remote = base
        local.update("T-003") { $0.title = "Local title" }
        remote.update("T-002") { $0.fields["agent_notes"] = .string("Remote notes") }
        try YAMLCodec.encode(remote).write(to: url, options: .atomic)
        let snapshot = ProjectSnapshot(project: local, baseline: base, sourceURL: url)
        let output = try ProjectFile.save(snapshot, to: staging, alreadyCoordinated: true)
        #expect(try ProjectFile.read(url) == remote)
        #expect(try ProjectFile.read(staging) == output)
        #expect(output.task("T-003")?.title == "Local title")
        #expect(output.task("T-002")?.text("agent_notes") == "Remote notes")
    }
    @MainActor @Test func invalidExternalSnapshotKeepsBoardThenRecovers() async throws {
        let document = KanbanDocument(); let base = try fixture()
        try await document.apply(snapshot: ProjectSnapshot(project: base, baseline: base), previous: nil)
        try await document.apply(snapshot: ProjectSnapshot(project: base, baseline: nil, diagnostic: "Unexpected end at line 3"), previous: nil)
        #expect(document.issue?.contains("line 3") == true)
        #expect(document.project == base)
        document.edit("Blocked edit", undoManager: nil) { $0.title = "Should not apply" }
        #expect(document.project == base)
        try await document.apply(snapshot: ProjectSnapshot(project: base, baseline: base), previous: nil)
        #expect(document.issue == nil)
    }

    @Test func parseErrorsIncludeSourceLocation() {
        do {
            _ = try YAMLCodec.decode(Data("groups: [unfinished\n".utf8))
            Issue.record("Malformed YAML was accepted")
        } catch {
            #expect(error.localizedDescription.contains("line"))
            #expect(error.localizedDescription.contains("column"))
        }
    }
    @Test func quotedScalarsKeepTheirStringTypes() throws {
        var p = try fixture()
        let values = ["yes", "true", "null", "2026-10-15", "0123", "1.2", "", "*alias", "!tag", "a: b", "# comment"]
        p.extra["strings"] = .array(values.map(YAMLValue.string))
        #expect(try YAMLCodec.decode(YAMLCodec.encode(p)) == p)
    }

}
