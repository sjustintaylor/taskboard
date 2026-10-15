import SwiftUI
import AppKit

struct TaskInspector: View {
    @Bindable var document: KanbanDocument
    let task: BoardTask
    let close: () -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var markdownPreview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Task Details").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close inspector (Escape)")
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(task.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    TextField("Task title", text: text("title"), axis: .vertical).font(.title3.weight(.semibold)).accessibilityIdentifier("taskTitle")
                    Picker("Status", selection: Binding(get: { task.status }, set: { status in edit("Change Status") { $0.status = status } })) {
                        ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Group", selection: Binding(get: { document.project.groupID(for: task.id) ?? "" }, set: { group in
                        document.edit("Change Group", undoManager: undoManager) { $0.move([task.id], group: group.isEmpty ? nil : group, changeGroup: true) }
                    })) {
                        Text("Ungrouped").tag("")
                        ForEach(document.project.groups) { Text($0.title).tag($0.id) }
                    }
                    if !document.project.unresolved(task).isEmpty {
                        Label("Unresolved: " + document.project.unresolved(task).joined(separator: ", "), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Text("Description").font(.headline)
                        Spacer()
                        Toggle("Preview Markdown", isOn: $markdownPreview).toggleStyle(.button).font(.caption)
                    }
                    if markdownPreview {
                        Text(LocalizedStringKey(task.text("description"))).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } else { editor(text("description"), label: "Description") }
                    section("Acceptance Criteria", hint: "One condition per line") { editor(list("acceptance_criteria"), label: "Acceptance criteria") }
                    section("Dependencies", hint: "Completed dependencies make Todo tasks eligible for the next brief.") {
                        if document.project.tasks.count < 2 { Text("No other tasks").foregroundStyle(.secondary).font(.caption) }
                        ForEach(document.project.tasks.filter { $0.id != task.id }) { dependency in
                            Toggle(isOn: Binding(get: { task.list("depends_on").contains(dependency.id) }, set: { selected in
                                edit("Change Dependencies") {
                                    var ids = $0.list("depends_on"); ids.removeAll { $0 == dependency.id }
                                    if selected { ids.append(dependency.id) }; $0.fields["depends_on"] = .array(ids.map(YAMLValue.string))
                                }
                            })) { Text("\(dependency.title) · \(dependency.status.title)").font(.caption) }
                        }
                    }
                    section("Agent Notes") { editor(text("agent_notes"), label: "Agent notes") }
                    section("Verification", hint: "One test or result per line") { editor(list("verification"), label: "Verification") }
                    if task.status == .doing {
                        Toggle("Ready for review", isOn: Binding(get: { task.readyForReview }, set: { ready in edit("Review Readiness") { $0.readyForReview = ready } }))
                        if task.readyForReview {
                            HStack {
                                Button("Approve → Done") { edit("Approve Task") { $0.status = .done } }.buttonStyle(.borderedProminent)
                                Button("Return to Work") { edit("Return to Work") { $0.readyForReview = false } }
                            }
                        }
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AgentBrief.make(task: task, project: document.project, fileURL: document.fileURL), forType: .string)
                    } label: { Label("Copy Task Brief", systemImage: "doc.on.clipboard") }.disabled(document.fileURL == nil)
                    if document.fileURL == nil { Text("Save the project to include its path in an agent brief.").font(.caption).foregroundStyle(.secondary) }
                }.padding(16)
            }.disabled(document.issue != nil)
        }.background(.background)
    }
    private func text(_ key: String) -> Binding<String> {
        Binding(get: { task.text(key) }, set: { value in
            if key == "title" && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            edit("Edit \(key.replacingOccurrences(of: "_", with: " ").capitalized)") { $0.fields[key] = .string(value) }
        })
    }
    private func list(_ key: String) -> Binding<String> {
        Binding(get: { task.list(key).joined(separator: "\n") }, set: { value in
            edit("Edit \(key.replacingOccurrences(of: "_", with: " ").capitalized)") { $0.fields[key] = .array(value.components(separatedBy: "\n").map(YAMLValue.string)) }
        })
    }
    private func edit(_ name: String, _ change: (inout BoardTask) -> Void) {
        document.edit(name, undoManager: undoManager) { $0.update(task.id, change) }
    }
    private func editor(_ binding: Binding<String>, label: String) -> some View {
        TextEditor(text: binding).font(.system(.body, design: .monospaced))
            .frame(minHeight: 80).padding(6).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(label)
    }
    private func section<Content: View>(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            content()
        }
    }
}
