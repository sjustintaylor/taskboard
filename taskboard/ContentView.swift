import SwiftUI
import AppKit

private enum BoardFilter: Hashable {
    case all, ungrouped, group(String)
    var groupID: String? { if case .group(let id) = self { return id }; return nil }
    static func forGroup(_ id: String?) -> BoardFilter { id.map(BoardFilter.group) ?? .ungrouped }
}

struct ContentView: View {
    @Bindable var document: KanbanDocument
    @Environment(\.undoManager) private var undoManager
    @State private var selection = Set<String>()
    @State private var inspectedID: String?
    @State private var collapsed = Set<String>()
    @State private var filter = BoardFilter.all
    @State private var search = ""
    @State private var groupEditor = false
    @State private var projectEditor = false
    @State private var deletingGroup: String?
    @State private var deletingTasks = false
    @State private var conflictDetails = false
    @FocusState private var searchFocused: Bool
    @FocusState private var boardFocused: Bool

    private var project: Project { document.project }
    private var visibleTasks: [BoardTask] {
        project.tasks.filter { task in
            (filter == .all || BoardFilter.forGroup(project.groupID(for: task.id)) == filter) &&
            (search.isEmpty || [task.title, task.id, task.text("description"), task.text("agent_notes")].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            overview
            if let issue = document.issue { issueBanner(issue) }
            HSplitView {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(TaskStatus.allCases) { status in column(status) }
                    }.padding(20)
                }
                .focusable().focused($boardFocused)
                .onKeyPress(.upArrow) { navigate(-1); return .handled }
                .onKeyPress(.downArrow) { navigate(1); return .handled }
                .onKeyPress(.leftArrow) { navigateColumn(-1); return .handled }
                .onKeyPress(.rightArrow) { navigateColumn(1); return .handled }
                .onKeyPress(.return) { inspectedID = selection.first; return .handled }
                if let id = inspectedID, let task = project.task(id) {
                    TaskInspector(document: document, task: task, close: { inspectedID = nil })
                        .frame(minWidth: 280, idealWidth: 330, maxWidth: 440)
                }
            }
            Divider()
            HStack {
                Image(systemName: "doc.text")
                Text(document.fileURL?.path ?? "Unsaved project — use File > Save")
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                if let url = document.fileURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
        }
        .background(DocumentWindowSetup(document: document).frame(width: 0, height: 0))
        .background(BoardKeyboardShortcuts(navigate: navigate, navigateColumn: navigateColumn,
            open: { inspectedID = selection.first },
            escape: {
                if inspectedID == nil { search = "" }
                inspectedID = nil; searchFocused = false; boardFocused = true
            }).frame(width: 0, height: 0))
        .frame(minWidth: 860, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar { toolbar }
        .searchable(text: $search, placement: .toolbar, prompt: "Search tasks")
        .searchFocused($searchFocused)
        .onExitCommand { inspectedID = nil; searchFocused = false; boardFocused = true }
        .task {
            while !Task.isCancelled {
                await document.refresh()
                try? await Task.sleep(for: .milliseconds(650))
            }
        }
        .onChange(of: project.tasks.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            if let inspectedID, !ids.contains(inspectedID) { self.inspectedID = nil }
        }
        .onChange(of: project.groups.map(\.id)) { _, ids in
            if let id = filter.groupID, !ids.contains(id) { filter = .all }
        }
        .sheet(isPresented: $groupEditor) { groupSheet }
        .sheet(isPresented: $projectEditor) { projectSheet }
        .sheet(isPresented: $conflictDetails) { conflictSheet }
        .confirmationDialog("Delete group? Its tasks will move to Ungrouped.", isPresented: Binding(get: { deletingGroup != nil }, set: { if !$0 { deletingGroup = nil } })) {
            Button("Delete Group", role: .destructive) {
                if let id = deletingGroup { edit("Delete Group") { $0.deleteGroup(id) }; if filter == .group(id) { filter = .all } }
                deletingGroup = nil
            }
        }
        .confirmationDialog("Delete selected tasks and remove references to them?", isPresented: $deletingTasks) {
            Button("Delete Tasks", role: .destructive) { edit("Delete Tasks") { $0.delete(selection) }; selection = []; inspectedID = nil }
        }
        .alert("Edit could not be applied", isPresented: Binding(get: { document.editError != nil }, set: { if !$0 { document.editError = nil } })) {
            Button("OK") { document.editError = nil }
        } message: { Text(document.editError ?? "") }
    }
    private var overview: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(project.title).font(.title2.weight(.semibold))
                Text("\(project.completed) of \(project.tasks.count) tasks complete").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(project.completed), total: Double(max(project.tasks.count, 1))).frame(width: 140)
                .accessibilityLabel("Overall project progress")
            Spacer()
            metric("Doing", count: project.tasks.filter { $0.status == .doing }.count, color: .blue)
            metric("Awaiting review", count: project.tasks.filter { $0.status == .doing && $0.readyForReview }.count, color: .orange)
        }.padding(20)
    }
    private func metric(_ title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)").font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { addTask(group: filter.groupID) } label: { Label("New Task", systemImage: "plus") }
                .keyboardShortcut("t", modifiers: [.command]).disabled(document.issue != nil)
            Button { groupEditor = true } label: { Label("Groups", systemImage: "rectangle.3.group") }
            Picker("Group filter", selection: $filter) {
                Text("All groups").tag(BoardFilter.all)
                Text("Ungrouped").tag(BoardFilter.ungrouped)
                ForEach(project.groups) { Text($0.title).tag(BoardFilter.group($0.id)) }
            }.frame(width: 160)
            Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }.keyboardShortcut("f").help("Search tasks (⌘F)")
            Button { if let task = project.nextTask { copyBrief(task) } } label: { Label("Copy Next Task Brief", systemImage: "doc.on.clipboard") }
                .disabled(project.nextTask == nil || document.fileURL == nil).help("Copy the first Todo task whose dependencies are complete. Save the project first.")
            Menu {
                Button("Project Details") { projectEditor = true }
                if !selection.isEmpty {
                    Menu("Move Selected to Group") {
                        Button("Ungrouped") { moveSelection(group: nil) }
                        ForEach(project.groups) { group in Button(group.title) { moveSelection(group: group.id) } }
                    }
                    Button("Delete Selected Tasks…", role: .destructive) { deletingTasks = true }
                }
            } label: { Label("More", systemImage: "ellipsis.circle") }
        }
    }
    private func column(_ status: TaskStatus) -> some View {
        let tasks = visibleTasks.filter { $0.status == status }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(status == .todo ? Color.secondary : status == .doing ? Color.blue : Color.green).frame(width: 8, height: 8)
                Text(status.title).font(.headline)
                Text("\(tasks.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }.padding(14)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if status == .todo {
                        ForEach(project.groups.filter { filter == .all || filter == .group($0.id) }) { group in groupSection(group, tasks: tasks.filter { project.groupID(for: $0.id) == group.id }) }
                        if filter == .all || filter == .ungrouped { groupSection(nil, tasks: tasks.filter { project.groupID(for: $0.id) == nil }) }
                    } else {
                        ForEach(tasks) { task in card(task) }
                        if tasks.isEmpty { Text(status == .doing ? "Move a task here to start work." : "Reviewed work appears here.").font(.callout).foregroundStyle(.secondary).padding(12) }
                    }
                    Color.clear.frame(height: 50).contentShape(Rectangle()).dropDestination(for: String.self) { ids, _ in drop(ids, status: status); return true }
                }.padding(12)
            }
        }
        .frame(width: 290).frame(maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .dropDestination(for: String.self) { ids, _ in drop(ids, status: status); return true }
        .accessibilityElement(children: .contain).accessibilityLabel("\(status.title) column")
    }
    private func groupSection(_ group: TaskGroup?, tasks: [BoardTask]) -> some View {
        let id = group.map { "group:" + $0.id } ?? "ungrouped"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
                } label: {
                    Image(systemName: collapsed.contains(id) ? "chevron.right" : "chevron.down").frame(width: 10)
                    Text(group?.title ?? "Ungrouped").fontWeight(.medium)
                }.buttonStyle(.plain).accessibilityLabel("Toggle \(group?.title ?? "Ungrouped")")
                Spacer()
                Text("\(tasks.count)").foregroundStyle(.secondary)
                Button { addTask(group: group?.id) } label: { Image(systemName: "plus") }.buttonStyle(.borderless).help("Add task to \(group?.title ?? "Ungrouped")")
            }.font(.callout)
            if let group {
                ProgressView(value: group.progress).tint(.green)
                Text("\(group.completed)/\(group.tasks.count) complete · \(Int(group.progress * 100))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !collapsed.contains(id) {
                ForEach(tasks) { task in card(task) }
                if tasks.isEmpty { Text("No Todo tasks").font(.caption).foregroundStyle(.tertiary).padding(.vertical, 8) }
            }
        }.padding(.vertical, 6)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in drop(ids, status: .todo, group: group?.id, changeGroup: true); return true }
    }
    private func card(_ task: BoardTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(String(task.id.prefix(12))).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if !project.unresolved(task).isEmpty { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("Unresolved dependencies: " + project.unresolved(task).joined(separator: ", ")) }
            }
            if task.status != .todo { Text(project.groupTitle(for: task.id)).font(.caption).foregroundStyle(.secondary) }
            if task.status == .doing && task.readyForReview { Label("Ready for review", systemImage: "checkmark.bubble").font(.caption.weight(.medium)).foregroundStyle(.orange) }
            if task.status == .done && !task.text("agent_notes").isEmpty { Text(task.text("agent_notes")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(selection.contains(task.id) ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection.contains(task.id) ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selection.contains(task.id) ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                if selection.contains(task.id) { selection.remove(task.id) } else { selection.insert(task.id) }
            } else { selection = [task.id] }
            inspectedID = task.id; boardFocused = true
        }
        .draggable(task.id)
        .dropDestination(for: String.self) { ids, _ in drop(ids, status: task.status, group: project.groupID(for: task.id), changeGroup: task.status == .todo, before: task.id); return true }
        .contextMenu {
            ForEach(TaskStatus.allCases) { status in Button("Move to \(status.title)") { edit("Move Task") { $0.move([task.id], status: status) } } }
            Menu("Move to Group") {
                Button("Ungrouped") { edit("Move Task") { $0.move([task.id], group: nil, changeGroup: true) } }
                ForEach(project.groups) { group in Button(group.title) { edit("Move Task") { $0.move([task.id], group: group.id, changeGroup: true) } } }
            }
            Button("Move Up") { reorderTask(task, offset: -1) }
            Button("Move Down") { reorderTask(task, offset: 1) }
            Divider()
            Button("Copy Task Brief") { copyBrief(task) }.disabled(document.fileURL == nil)
            Button("Delete Task…", role: .destructive) { selection = [task.id]; deletingTasks = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(task.status.title), \(project.groupTitle(for: task.id))\(task.readyForReview ? ", ready for review" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selection = [task.id]; inspectedID = task.id }
    }
    private func reorderTask(_ task: BoardTask, offset: Int) {
        let siblings = project.tasks.filter { project.groupID(for: $0.id) == project.groupID(for: task.id) && $0.status == task.status }
        guard let index = siblings.firstIndex(where: { $0.id == task.id }), siblings.indices.contains(index + offset) else { return }
        let before = offset < 0 ? siblings[index - 1].id : (siblings.indices.contains(index + 2) ? siblings[index + 2].id : nil)
        edit("Reorder Task") { $0.move([task.id], before: before) }
    }
    private func drop(_ strings: [String], status: TaskStatus, group: String? = nil, changeGroup: Bool = false, before: String? = nil) {
        let ids = Set(strings).intersection(project.tasks.map(\.id))
        guard !ids.isEmpty else { return }
        edit("Move Tasks") { $0.move(ids, status: status, group: group, changeGroup: changeGroup, before: before) }
    }
    private func edit(_ name: String, _ change: (inout Project) -> Void) { document.edit(name, undoManager: undoManager, change) }
    private func addTask(group: String?) {
        let task = BoardTask()
        search = ""
        edit("New Task") { $0.insert(task, group: group) }
        selection = [task.id]; inspectedID = task.id
        collapsed.remove(group.map { "group:" + $0 } ?? "ungrouped")
    }
    private func moveSelection(group: String?) { edit("Move Selected Tasks") { $0.move(selection, group: group, changeGroup: true) } }
    private func copyBrief(_ task: BoardTask) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(AgentBrief.make(task: task, project: project, fileURL: document.fileURL), forType: .string) }
    private func navigate(_ step: Int) {
        let ordered = TaskStatus.allCases.flatMap { status in visibleTasks.filter { $0.status == status } }
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex { selection.contains($0.id) } ?? (step > 0 ? -1 : ordered.count)
        let next = ordered[min(max(index + step, 0), ordered.count - 1)]
        selection = [next.id]; if inspectedID != nil { inspectedID = next.id }
        collapsed.remove(project.groupID(for: next.id).map { "group:" + $0 } ?? "ungrouped")
    }
    private func navigateColumn(_ step: Int) {
        guard let id = selection.first, let task = project.task(id), let index = TaskStatus.allCases.firstIndex(of: task.status), TaskStatus.allCases.indices.contains(index + step), let next = visibleTasks.first(where: { $0.status == TaskStatus.allCases[index + step] }) else { return }
        selection = [next.id]; if inspectedID != nil { inspectedID = next.id }
    }
    private func issueBanner(_ issue: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(issue).font(.callout).textSelection(.enabled)
            Spacer()
            if document.conflict { Button("Resolve…") { conflictDetails = true } }
            else { Button("Retry") { Task { await document.refresh() } } }
            Button("Save Local Copy…") { document.exportLocalAndReload() }
        }.padding(12).background(.orange.opacity(0.08))
    }
    private var groupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Groups").font(.title2.bold())
            Text("Groups are ordered phases. Deleting a group preserves its tasks.").foregroundStyle(.secondary)
            ScrollView {
                ForEach(project.groups) { group in
                    HStack {
                        TextField("Group title", text: Binding(get: { project.groups.first { $0.id == group.id }?.title ?? "" }, set: { title in
                            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            edit("Rename Group") { if let i = $0.groups.firstIndex(where: { $0.id == group.id }) { $0.groups[i].title = title } }
                        }))
                        Button { edit("Reorder Group") { $0.reorderGroup(group.id, offset: -1) } } label: { Image(systemName: "arrow.up") }.help("Move group up")
                        Button { edit("Reorder Group") { $0.reorderGroup(group.id, offset: 1) } } label: { Image(systemName: "arrow.down") }.help("Move group down")
                        Button(role: .destructive) { groupEditor = false; deletingGroup = group.id } label: { Image(systemName: "trash") }.help("Delete group")
                    }
                }
            }
            HStack {
                Button("New Group") { edit("New Group") { $0.groups.append(TaskGroup()) } }
                Spacer(); Button("Done") { groupEditor = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540, height: 360)
    }
    private var projectSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Details").font(.title2.bold())
            TextField("Project title", text: Binding(get: { project.title }, set: { title in
                if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { edit("Rename Project") { $0.title = title } }
            }))
            Text("Description").font(.headline)
            TextEditor(text: Binding(get: { project.metadata["description"]?.string ?? "" }, set: { description in edit("Project Description") { $0.metadata["description"] = .string(description) } }))
            Button("Done") { projectEditor = false }.keyboardShortcut(.defaultAction)
        }.padding(24).frame(width: 500, height: 340)
    }
    private var conflictSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resolve External Changes").font(.title2.bold())
            Text("Both versions are preserved. Export the local board to a separate file, then load the external version. The exported file can be opened to reconcile remaining edits.")
            HStack {
                conflictPreview("Local board", project: project)
                if let remote = document.externalProject { conflictPreview("External file", project: remote) }
            }
            HStack {
                Button("Keep Both Pending") { conflictDetails = false }
                Spacer()
                Button("Export Local and Load External…") { document.exportLocalAndReload(); if !document.conflict { conflictDetails = false } }
            }
        }.padding(24).frame(width: 820, height: 540)
    }
    private func conflictPreview(_ title: String, project: Project) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            ScrollView { Text((try? YAMLCodec.encode(project)).flatMap { String(data: $0, encoding: .utf8) } ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.frame(maxWidth: .infinity)
    }
}
