import SwiftUI
import AppKit

struct TaskInspector: View {
    @Bindable var document: KanbanDocument
    let task: BoardTask
    let close: () -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var managingDependencies = false
    @State private var dependencySearch = ""

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
                    Text(task.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
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
                    section("Description") {
                        MarkdownEditor(markdown: text("description"), label: "Description")
                    }
                    section("Acceptance Criteria") {
                        ForEach(Array(task.list("acceptance_criteria").enumerated()), id: \.offset) { index, _ in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Criterion \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(role: .destructive) {
                                        edit("Remove Criterion") {
                                            var items = $0.list("acceptance_criteria")
                                            guard items.indices.contains(index) else { return }
                                            items.remove(at: index)
                                            $0.fields["acceptance_criteria"] = .array(items.map(YAMLValue.string))
                                        }
                                    } label: { Image(systemName: "minus.circle") }.help("Remove criterion")
                                }
                                MarkdownEditor(markdown: criterion(index), label: "Criterion \(index + 1)")
                            }
                        }
                        Button("Add Criterion", systemImage: "plus") {
                            edit("Add Criterion") { $0.fields["acceptance_criteria"] = .array(($0.list("acceptance_criteria") + [""]).map(YAMLValue.string)) }
                        }
                    }
                    section("Dependencies", hint: "Completed dependencies make Todo tasks eligible for the next brief.") {
                        if task.list("depends_on").isEmpty { Text("No dependencies").font(.caption).foregroundStyle(.secondary) }
                        ForEach(task.list("depends_on"), id: \.self) { id in
                            HStack {
                                if let dependency = document.project.task(id) {
                                    VStack(alignment: .leading) {
                                        Text(dependency.title)
                                        Text("\(id) · \(dependency.status.title)").foregroundStyle(.secondary)
                                    }.font(.caption)
                                } else { Text("Missing task: \(id)").font(.caption) }
                                Spacer()
                                Button { setDependency(id, selected: false) } label: { Image(systemName: "minus.circle") }
                                    .help("Remove dependency")
                            }
                        }
                        Button("Manage Dependencies…") { managingDependencies = true }
                            .popover(isPresented: $managingDependencies) { dependencyPicker }
                    }
                    section("Agent Notes") { editor(text("agent_notes"), label: "Agent notes") }
                    section("Verification", hint: "One test or result per line") { editor(list("verification"), label: "Verification") }
                    if task.status == .doing {
                        Button("Send to Review") { edit("Send to Review") { $0.status = .review } }
                    }
                    if task.status == .review {
                        HStack {
                            Button("Approve → Done") { edit("Approve Task") { $0.status = .done } }.buttonStyle(.borderedProminent)
                            Button("Return to Work") { edit("Return to Work") { $0.status = .doing } }
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
    private var dependencyCandidates: [BoardTask] {
        document.project.tasks.filter {
            $0.id != task.id && (dependencySearch.isEmpty || $0.title.localizedCaseInsensitiveContains(dependencySearch) || $0.id.localizedCaseInsensitiveContains(dependencySearch))
        }
    }
    private var dependencyPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Dependencies").font(.headline)
            TextField("Search title or ID", text: $dependencySearch)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if dependencyCandidates.isEmpty {
                        Text(dependencySearch.isEmpty ? "No other tasks" : "No matching tasks").foregroundStyle(.secondary)
                    }
                    ForEach(dependencyCandidates) { candidate in
                        let selected = task.list("depends_on").contains(candidate.id)
                        let cycle = document.project.wouldCreateDependencyCycle(taskID: task.id, dependencyID: candidate.id)
                        Toggle(isOn: Binding(get: { selected }, set: { setDependency(candidate.id, selected: $0) })) {
                            VStack(alignment: .leading) {
                                Text(candidate.title)
                                Text("\(candidate.id) · \(candidate.status.title)").font(.caption).foregroundStyle(.secondary)
                                if cycle && !selected { Text("Would create a dependency cycle").font(.caption).foregroundStyle(.orange) }
                            }
                        }.disabled(cycle && !selected)
                    }
                }
            }.frame(height: 280)
            HStack { Spacer(); Button("Done") { managingDependencies = false } }
        }.padding(16).frame(width: 360)
    }
    private func setDependency(_ id: String, selected: Bool) {
        guard !selected || !document.project.wouldCreateDependencyCycle(taskID: task.id, dependencyID: id) else { return }
        edit("Change Dependencies") {
            var ids = $0.list("depends_on"); ids.removeAll { $0 == id }
            if selected { ids.append(id) }
            $0.fields["depends_on"] = .array(ids.map(YAMLValue.string))
        }
    }
    private func criterion(_ index: Int) -> Binding<String> {
        Binding(get: {
            let items = document.project.task(task.id)?.list("acceptance_criteria") ?? []
            return items.indices.contains(index) ? items[index] : ""
        }, set: { value in
            edit("Edit Criterion") {
                var items = $0.list("acceptance_criteria")
                guard items.indices.contains(index) else { return }
                items[index] = value
                $0.fields["acceptance_criteria"] = .array(items.map(YAMLValue.string))
            }
        })
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
