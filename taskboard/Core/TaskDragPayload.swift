import CoreTransferable
import UniformTypeIdentifiers
import Foundation

extension UTType {
    static let taskboardTask = UTType(exportedAs: "com.taskboard.task-drag", conformingTo: .data)
}

struct TaskDragPayload: Codable, Transferable, Sendable {
    let documentID: UUID
    let taskID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .taskboardTask)
    }
}
