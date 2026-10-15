import Foundation

enum AgentBrief {
    static func make(task: BoardTask, project: Project, fileURL: URL?) -> String {
        let dependencies = task.list("depends_on").map { id in
            let dependency = project.task(id)
            return "- \(id): \(dependency?.title ?? "Missing") [\(dependency?.status.rawValue ?? "unknown")]"
        }.joined(separator: "\n")
        return """
        # Implementation brief: \(task.id) — \(task.title)
        Project: \(project.title)
        Group: \(project.groupTitle(for: task.id))
        Project file: \(fileURL?.path ?? "UNSAVED — save the project before giving this brief to an agent")

        ## Task
        \(task.text("description"))

        ## Acceptance criteria
        \(task.list("acceptance_criteria").map { "- " + $0.replacingOccurrences(of: "\n", with: "\n  ") }.joined(separator: "\n"))

        ## Dependencies
        \(dependencies.isEmpty ? "None." : dependencies)

        ## Existing progress
        \(task.text("agent_notes"))

        ## File editing contract
        Read the current project file before every edit. Preserve all IDs, unrelated tasks,
        unknown fields, grouping and order. Modify only fields required for this task.
        Keep valid UTF-8 YAML; do not introduce tags, anchors, aliases or timestamps.
        Move \(task.id) to status: doing when work starts and clear ready_for_review. Record material implementation
        changes in agent_notes and tests run with results in verification.
        When implementation is ready, set status: review and ready_for_review: true.
        Final approval and the move to done belong to the developer unless explicitly instructed otherwise.
        """
    }
}
