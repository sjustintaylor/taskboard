import Foundation
import Yams

enum YAMLCodec {
    static func decode(_ data: Data) throws -> Project {
        do { return try parse(data) }
        catch let error as YamlError { throw BoardError(String(describing: error)) }
    }
    private static func parse(_ data: Data) throws -> Project {
        guard let text = String(data: data, encoding: .utf8) else { throw BoardError("The project must be UTF-8 text.") }
        let parser = try Parser(yaml: text)
        guard let node = try parser.singleRoot() else { throw BoardError("The project file is empty. Expected format_version, project, groups and ungrouped.") }
        let value = try withExtendedLifetime(parser) { try read(node, path: "document") }
        return try project(from: value)
    }

    private static func read(_ node: Node, path: String, depth: Int = 0) throws -> YAMLValue {
        guard depth < 64 else { throw BoardError("\(path): nesting exceeds 64 levels.") }
        guard node.anchor == nil, node.alias == nil else { throw BoardError("\(path): YAML anchors and aliases are not supported.") }
        let tag = node.tag.rawValue
        switch node {
        case .scalar(let scalar):
            switch tag {
            case "tag:yaml.org,2002:str": return .string(scalar.string)
            case "tag:yaml.org,2002:int":
                guard let n = Int(scalar.string) else { throw BoardError("\(path): use a decimal integer.") }; return .integer(n)
            case "tag:yaml.org,2002:bool":
                guard ["true", "false"].contains(scalar.string) else { throw BoardError("\(path): use true or false; quote text values.") }
                return .boolean(scalar.string == "true")
            default: throw BoardError("\(path): unsupported YAML type \(tag). Quote dates, numbers used as text, and null-like strings.")
            }
        case .sequence(let sequence):
            guard tag == "tag:yaml.org,2002:seq" else { throw BoardError("\(path): custom YAML tags are not supported.") }
            return .array(try sequence.enumerated().map { try read($0.element, path: "\(path)[\($0.offset)]", depth: depth + 1) })
        case .mapping(let mapping):
            guard tag == "tag:yaml.org,2002:map" else { throw BoardError("\(path): custom YAML tags are not supported.") }
            var result: [String: YAMLValue] = [:]
            for (key, value) in mapping {
                guard case .string(let name) = try read(key, path: path, depth: depth + 1) else { throw BoardError("\(path): field names must be strings.") }
                guard result[name] == nil else { throw BoardError("\(path): duplicate field '\(name)'.") }
                result[name] = try read(value, path: path + "." + name, depth: depth + 1)
            }
            return .object(result)
        case .alias: throw BoardError("\(path): aliases are not supported.")
        }
    }

    static func project(from value: YAMLValue) throws -> Project {
        var root = try object(value, "document")
        guard root.removeValue(forKey: "format_version") == .integer(1) else { throw BoardError("format_version must be the supported integer 1. This file has not been modified.") }
        let metadata = try object(root.removeValue(forKey: "project"), "project")
        try requiredString(metadata, "title", "project")
        try optionalString(metadata, "description", "project")
        let groups = try array(root.removeValue(forKey: "groups"), "groups").enumerated().map { i, value -> TaskGroup in
            let path = "groups[\(i)]"
            var fields = try object(value, path)
            try requiredString(fields, "id", path); try requiredString(fields, "title", path)
            try optionalString(fields, "description", path)
            let tasks = try array(fields.removeValue(forKey: "tasks"), path + ".tasks").enumerated().map { try task($0.element, "\(path).tasks[\($0.offset)]") }
            return TaskGroup(fields: fields, tasks: tasks)
        }
        let ungrouped = try array(root.removeValue(forKey: "ungrouped"), "ungrouped").enumerated().map { try task($0.element, "ungrouped[\($0.offset)]") }
        let project = Project(extra: root, metadata: metadata, groups: groups, ungrouped: ungrouped)
        try validate(project)
        return project
    }
    private static func task(_ value: YAMLValue, _ path: String) throws -> BoardTask {
        let fields = try object(value, path)
        for key in ["id", "title", "status"] { try requiredString(fields, key, path) }
        guard TaskStatus(rawValue: fields["status"]!.string!) != nil else { throw BoardError("\(path).status must be todo, doing or done.") }
        for key in ["description", "agent_notes"] { try optionalString(fields, key, path) }
        for key in ["acceptance_criteria", "depends_on", "verification"] {
            if let value = fields[key] {
                for item in try array(value, path + "." + key) {
                    guard item.string != nil else { throw BoardError("\(path).\(key) must contain strings.") }
                }
            }
        }
        if let value = fields["ready_for_review"], case .boolean = value {} else if fields["ready_for_review"] != nil { throw BoardError("\(path).ready_for_review must be true or false.") }
        return BoardTask(fields: fields)
    }
    static func validate(_ project: Project) throws {
        guard Set(project.groups.map(\.id)).count == project.groups.count else { throw BoardError("Group IDs must be unique.") }
        let tasks = project.tasks
        guard Set(tasks.map(\.id)).count == tasks.count else { throw BoardError("Task IDs must be unique across all groups and Ungrouped.") }
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var visiting = Set<String>(), visited = Set<String>()
        func visit(_ id: String) throws {
            if visiting.contains(id) { throw BoardError("Circular dependency involving \(id). Remove a depends_on reference to break the cycle.") }
            if visited.contains(id) { return }
            visiting.insert(id)
            for dependency in byID[id]!.list("depends_on") {
                guard byID[dependency] != nil else { throw BoardError("\(id).depends_on references missing task '\(dependency)'.") }
                try visit(dependency)
            }
            visiting.remove(id); visited.insert(id)
        }
        for task in tasks { try visit(task.id) }
    }
    private static func object(_ value: YAMLValue?, _ path: String) throws -> [String: YAMLValue] {
        guard let result = value?.object else { throw BoardError("\(path) must be a mapping.") }; return result
    }
    private static func array(_ value: YAMLValue?, _ path: String) throws -> [YAMLValue] {
        guard let result = value?.array else { throw BoardError("\(path) must be a sequence (use [] when empty).") }; return result
    }
    private static func requiredString(_ fields: [String: YAMLValue], _ key: String, _ path: String) throws {
        guard let value = fields[key]?.string, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BoardError("\(path).\(key) must be a non-empty string.") }
    }
    private static func optionalString(_ fields: [String: YAMLValue], _ key: String, _ path: String) throws {
        if let value = fields[key], value.string == nil { throw BoardError("\(path).\(key) must be a string.") }
    }
    static func value(_ project: Project) -> YAMLValue {
        var root = project.extra
        root["format_version"] = .integer(1); root["project"] = .object(project.metadata)
        root["groups"] = .array(project.groups.map { group in
            var fields = group.fields; fields["tasks"] = .array(group.tasks.map { .object($0.fields) }); return .object(fields)
        })
        root["ungrouped"] = .array(project.ungrouped.map { .object($0.fields) })
        return .object(root)
    }
    static func encode(_ project: Project) throws -> Data {
        // Validation also covers UI-created values, not just parsed documents.
        _ = try self.project(from: value(project))
        return Data(try serialize(node: node(value(project)), indent: 2, width: 100, allowUnicode: true).utf8)
    }
    private static func node(_ value: YAMLValue, key: String = "") -> Node {
        switch value {
        case .string(let s): return Node(s, Tag(.str), ["description", "agent_notes"].contains(key) || s.contains("\n") ? .literal : .doubleQuoted)
        case .integer(let n): return Node(String(n), Tag(.int), .plain)
        case .boolean(let b): return Node(b ? "true" : "false", Tag(.bool), .plain)
        case .array(let values): return Node(values.map { node($0) })
        case .object(let fields):
            let order = ["format_version", "project", "groups", "ungrouped", "id", "title", "status", "description", "acceptance_criteria", "depends_on", "agent_notes", "verification", "ready_for_review", "tasks"]
            let keys = fields.keys.sorted { a, b in
                let i = order.firstIndex(of: a) ?? 100, j = order.firstIndex(of: b) ?? 100
                return i == j ? a < b : i < j
            }
            return Node(keys.map { (Node($0, Tag(.str)), node(fields[$0]!, key: $0)) })
        }
    }
}
