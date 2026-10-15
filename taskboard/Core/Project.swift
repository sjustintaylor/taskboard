import Foundation

// Unknown fields stay in the value tree and survive all supported UI edits.
indirect enum YAMLValue: Equatable, Sendable {
    case string(String), integer(Int), boolean(Bool), array([YAMLValue]), object([String: YAMLValue])
    var string: String? { if case .string(let x) = self { return x }; return nil }
    var array: [YAMLValue]? { if case .array(let x) = self { return x }; return nil }
    var object: [String: YAMLValue]? { if case .object(let x) = self { return x }; return nil }
}

enum TaskStatus: String, CaseIterable, Identifiable, Sendable {
    case todo, doing, done
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct BoardTask: Identifiable, Equatable, Sendable {
    var fields: [String: YAMLValue]
    init(id: String = "T-" + UUID().uuidString, title: String = "New task") {
        fields = ["id": .string(id), "title": .string(title), "status": .string("todo")]
    }
    init(fields: [String: YAMLValue]) { self.fields = fields }
    var id: String { fields["id"]!.string! }
    var title: String { get { text("title") } set { fields["title"] = .string(newValue) } }
    var status: TaskStatus {
        get { TaskStatus(rawValue: text("status"))! }
        set { fields["status"] = .string(newValue.rawValue); if newValue != .doing { readyForReview = false } }
    }
    var readyForReview: Bool {
        get { fields["ready_for_review"] == .boolean(true) }
        set { fields["ready_for_review"] = .boolean(newValue) }
    }
    func text(_ key: String) -> String { fields[key]?.string ?? "" }
    func list(_ key: String) -> [String] { fields[key]?.array?.compactMap(\.string) ?? [] }
}

struct TaskGroup: Identifiable, Equatable, Sendable {
    var fields: [String: YAMLValue]
    var tasks: [BoardTask]
    init(id: String = "G-" + UUID().uuidString, title: String = "New group", tasks: [BoardTask] = []) {
        fields = ["id": .string(id), "title": .string(title)]; self.tasks = tasks
    }
    init(fields: [String: YAMLValue], tasks: [BoardTask]) { self.fields = fields; self.tasks = tasks }
    var id: String { fields["id"]!.string! }
    var title: String { get { fields["title"]!.string! } set { fields["title"] = .string(newValue) } }
    var completed: Int { tasks.filter { $0.status == .done }.count }
    var progress: Double { tasks.isEmpty ? 0 : Double(completed) / Double(tasks.count) }
}

struct Project: Equatable, Sendable {
    var extra: [String: YAMLValue] = [:]
    var metadata: [String: YAMLValue] = ["title": .string("Untitled Project")]
    var groups: [TaskGroup] = []
    var ungrouped: [BoardTask] = []
    var title: String { get { metadata["title"]!.string! } set { metadata["title"] = .string(newValue) } }
    var tasks: [BoardTask] { groups.flatMap(\.tasks) + ungrouped }
    var completed: Int { tasks.filter { $0.status == .done }.count }
    func task(_ id: String) -> BoardTask? { tasks.first { $0.id == id } }
    func groupID(for id: String) -> String? { groups.first { $0.tasks.contains { $0.id == id } }?.id }
    func groupTitle(for id: String) -> String { groups.first { $0.id == groupID(for: id) }?.title ?? "Ungrouped" }
    func unresolved(_ task: BoardTask) -> [String] { task.list("depends_on").filter { self.task($0)?.status != .done } }
    var nextTask: BoardTask? { tasks.first { $0.status == .todo && unresolved($0).isEmpty } }

    mutating func update(_ id: String, _ edit: (inout BoardTask) -> Void) {
        for g in groups.indices {
            if let t = groups[g].tasks.firstIndex(where: { $0.id == id }) { edit(&groups[g].tasks[t]); return }
        }
        if let t = ungrouped.firstIndex(where: { $0.id == id }) { edit(&ungrouped[t]) }
    }
    mutating func remove(_ ids: Set<String>) {
        for g in groups.indices { groups[g].tasks.removeAll { ids.contains($0.id) } }
        ungrouped.removeAll { ids.contains($0.id) }
    }
    mutating func delete(_ ids: Set<String>) {
        remove(ids)
        for task in tasks { update(task.id) { $0.fields["depends_on"] = .array($0.list("depends_on").filter { !ids.contains($0) }.map(YAMLValue.string)) } }
    }
    mutating func insert(_ task: BoardTask, group: String?, before: String? = nil) {
        if let g = groups.firstIndex(where: { $0.id == group }) {
            let index = groups[g].tasks.firstIndex { $0.id == before } ?? groups[g].tasks.count
            groups[g].tasks.insert(task, at: index)
        } else {
            let index = ungrouped.firstIndex { $0.id == before } ?? ungrouped.count
            ungrouped.insert(task, at: index)
        }
    }
    mutating func move(_ ids: Set<String>, status: TaskStatus? = nil, group: String? = nil, changeGroup: Bool = false, before: String? = nil) {
        guard before.map({ !ids.contains($0) }) ?? true else { return }
        let moving = tasks.filter { ids.contains($0.id) }.map { ($0, groupID(for: $0.id)) }
        remove(ids)
        for (var task, originalGroup) in moving {
            if let status { task.status = status }
            insert(task, group: changeGroup ? group : originalGroup, before: before)
        }
    }
    mutating func deleteGroup(_ id: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        ungrouped += groups.remove(at: index).tasks
    }
    mutating func reorderGroup(_ id: String, offset: Int) {
        guard let index = groups.firstIndex(where: { $0.id == id }), groups.indices.contains(index + offset) else { return }
        groups.swapAt(index, index + offset)
    }
}

struct BoardError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
