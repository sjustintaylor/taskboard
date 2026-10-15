import Foundation

struct ProjectSnapshot: Sendable {
    var project: Project
    var baseline: Project?
    var sourceURL: URL? = nil
    var diagnostic: String? = nil
}

enum ProjectFile {
    struct Revision: Sendable {
        var project: Project
        var modificationDate: Date?
    }
    static func read(_ url: URL, alreadyCoordinated: Bool = false, coordinator: NSFileCoordinator? = nil) throws -> Project {
        try readRevision(url, alreadyCoordinated: alreadyCoordinated, coordinator: coordinator).project
    }
    static func readRevision(_ url: URL, alreadyCoordinated: Bool = false, coordinator: NSFileCoordinator? = nil) throws -> Revision {
        func load(_ source: URL) throws -> Revision {
            let bytes = try Data(contentsOf: source)
            let project = try YAMLCodec.decode(bytes)
            let date = try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as? Date
            guard try Data(contentsOf: source) == bytes else { throw BoardError("The file changed while reading. Waiting for a stable version.") }
            return Revision(project: project, modificationDate: date)
        }
        if alreadyCoordinated { return try load(url) }
        var coordinationError: NSError?
        var result: Result<Revision, Error> = .failure(BoardError("Unable to read the project."))
        (coordinator ?? NSFileCoordinator()).coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try load(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// SwiftUI/NSDocument coordinates its writer and may supply a staging destination.
    /// Compare against the authoritative source URL, then write the supplied destination.
    @discardableResult
    static func save(_ snapshot: ProjectSnapshot, to url: URL, alreadyCoordinated: Bool = false) throws -> Project {
        var coordinationError: NSError?
        var result: Result<Project, Error> = .failure(BoardError("Unable to save the project."))
        let write: (URL) -> Void = { destination in
            result = Result {
                let source = snapshot.sourceURL ?? destination
                let exists = FileManager.default.fileExists(atPath: source.path)
                let original = exists ? try Data(contentsOf: source) : nil
                var output = snapshot.project
                var unchanged = false
                if let original {
                    let disk = try YAMLCodec.decode(original)
                    if let base = snapshot.baseline { output = try ProjectMerge.merge(base: base, local: output, remote: disk) }
                    else if disk != output { throw BoardError("The destination already contains a different project. Choose a new filename.") }
                    unchanged = output == disk
                    if unchanged && source.standardizedFileURL == destination.standardizedFileURL { return disk }
                } else if snapshot.baseline != nil && snapshot.sourceURL != nil {
                    throw BoardError("The project file was removed. Save a copy to recover local changes.")
                } else if snapshot.baseline != nil && !alreadyCoordinated {
                    throw BoardError("The project file was removed. Save a copy to recover local changes.")
                }
                // Preserve formatting even when NSDocument requests an unchanged staging copy.
                let data = try unchanged ? original! : YAMLCodec.encode(output)
                let latest = FileManager.default.fileExists(atPath: source.path) ? try Data(contentsOf: source) : nil
                guard original == latest else { throw BoardError("The file changed during saving. Retry after the external edit finishes.") }
                try data.write(to: destination, options: .atomic)
                return output
            }
        }
        if alreadyCoordinated { write(url) }
        else { NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError, byAccessor: write) }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
