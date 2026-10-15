import Foundation

/// Three-way field merge. ID sequences merge entity edits independently of their order.
/// Ambiguous ordering, concurrent moves, and delete/edit collisions require a decision.
enum ProjectMerge {
    static func merge(base: Project, local: Project, remote: Project) throws -> Project {
        let value = try mergeValue(YAMLCodec.value(base), YAMLCodec.value(local), YAMLCodec.value(remote), path: "document")
        return try YAMLCodec.project(from: value!)
    }
    private static func mergeValue(_ base: YAMLValue?, _ local: YAMLValue?, _ remote: YAMLValue?, path: String) throws -> YAMLValue? {
        if local == remote { return local }
        if local == base { return remote }
        if remote == base { return local }
        if case .object(let b) = base, case .object(let l) = local, case .object(let r) = remote {
            var merged: [String: YAMLValue] = [:]
            for key in Set(b.keys).union(l.keys).union(r.keys) {
                merged[key] = try mergeValue(b[key], l[key], r[key], path: path + "." + key)
            }
            return .object(merged)
        }
        if case .array(let b) = base, case .array(let l) = local, case .array(let r) = remote,
           let bi = identifiers(b), let li = identifiers(l), let ri = identifiers(r) {
            let order: [String]
            if li == ri { order = li }
            else if li == bi { order = ri }
            else if ri == bi { order = li }
            else { throw BoardError("Conflicting order or membership at \(path). Both versions are retained.") }
            let bm = Dictionary(uniqueKeysWithValues: zip(bi, b)), lm = Dictionary(uniqueKeysWithValues: zip(li, l)), rm = Dictionary(uniqueKeysWithValues: zip(ri, r))
            var merged: [String: YAMLValue] = [:]
            for id in Set(bi).union(li).union(ri) { merged[id] = try mergeValue(bm[id], lm[id], rm[id], path: path + "[\(id)]") }
            return .array(order.compactMap { merged[$0] })
        }
        throw BoardError("Conflicting changes at \(path). Both versions are retained.")
    }
    private static func identifiers(_ array: [YAMLValue]) -> [String]? {
        let ids = array.compactMap { $0.object?["id"]?.string }
        return ids.count == array.count && Set(ids).count == ids.count ? ids : nil
    }
}
