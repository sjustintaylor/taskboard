# AI Influence level:
AIL4: The bot did most of it.

# Taskboard

Native macOS Kanban for supervising external coding agents. Each project is a single UTF-8 `.kanban.yaml` file. No database, account, service, runtime network access, or agent process is required.

## Features

- Three workflow states: **Todo**, **Doing**, and **Done**.
- Ordered, collapsible groups with completion progress, search, and filtering.
- Rich text descriptions and individual acceptance criteria, saved as Markdown in YAML.
- Compact dependency lists with a searchable dependency manager.
- Recent-boards welcome window and a persistent, adjustable board/inspector split.
- Developer approval for review-ready work, plus generated implementation briefs for external agents.
- Native document windows, autosave, drag-and-drop, keyboard navigation, and undo/redo.
- External-file reload, schema validation, independent-edit merging, and conflict recovery.

## Quick start

1. Build and run the app using the instructions below.
2. Open [the example project](Examples/Notes.kanban.yaml), or create a project with **⌘N**.
3. Save the document as `Project.kanban.yaml`, preferably alongside the source code it describes.
4. Add groups and tasks, then use **Copy Next Task Brief** to hand eligible work to an external coding agent.
5. Review the agent's notes and verification results, then choose **Approve → Done**.

## Build and run

Requires **macOS 27 or later and Xcode 27**. The deployment target deliberately uses SwiftUI's new `Document` / `DocumentReader` / `DocumentWriter` APIs. Open `taskboard.xcodeproj`, select the `taskboard` scheme and **My Mac**, then Run. Xcode resolves the pinned **Yams 6.2.2** and **swift-markdown 0.7.3** packages on the first build; subsequent app use is fully offline.

```sh
xcodebuild -project taskboard.xcodeproj -scheme taskboard \
  -destination 'platform=macOS' -derivedDataPath /tmp/taskboard-build \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project taskboard.xcodeproj -scheme taskboard \
  -destination 'platform=macOS' -derivedDataPath /tmp/taskboard-build \
  CODE_SIGNING_ALLOWED=NO -only-testing:taskboardTests test
```

The local unsigned development app is produced at `/tmp/taskboard-build/Build/Products/Debug/taskboard.app`. Distribution signing and notarization are separate release steps.

## Using the board

- **⌘N / ⌘O / ⌘S:** new project, open, save. Save projects with the `.kanban.yaml` suffix. Multiple projects open in separate windows.
- **⌘T:** new task. Select a card to edit it in the right inspector. **Escape** closes the inspector; arrow keys navigate cards; **Return** opens the selected task.
- **⌘F:** search. The group picker filters all three columns. Overall and group progress always count the entire project, regardless of the filter.
- **Groups:** create, rename and reorder groups. Group deletion requires confirmation and moves all its tasks to Ungrouped.
- Drag tasks to columns to change status, to Todo groups to change group, or onto a card to insert before it. The context menu also provides status, group and ordering actions. Persisted ordering follows the schema's group and task sequences; flat columns retain this canonical order.
- Launching without restored boards shows **Welcome to Taskboard**, with recent files, **New Board**, and **Open Board…**. The welcome window also returns after the last board closes and is available from the Window menu.
- Opening a task starts with a two-thirds board / one-third inspector split. Drag the divider to adjust it; the app remembers the ratio. Closing the inspector gives the board the full width.
- Description and acceptance criteria support bold (⌘B), italic (⌘I), links (⌘K), and lists. Each criterion is edited separately; Return inserts a newline within it. **Markdown** mode provides source editing. Unsupported formatting stays in source mode to preserve its contents. Pasted text uses plain text formatting; arbitrary RTF/HTML styles are not imported.
- **Manage Dependencies…** searches tasks by title or ID. Only selected dependencies appear in the inspector; additions that would create cycles are disabled.
- **⌘-click** selects multiple cards. **More → Move Selected to Group** moves the selection together. Deleting tasks requires confirmation and removes dependencies pointing to them.
- Descriptions and notes accept Markdown. Description preview supports inline Markdown; source editors retain code blocks and all Markdown text verbatim.
- **Copy Task Brief** includes task details, criteria, dependencies, file path and the agent editing contract. **Copy Next Task Brief** chooses the first Todo task with all dependencies Done. Save the document first to establish the path.
- Agents set `status: doing`, update `agent_notes` and `verification`, then set `ready_for_review: true`. **Approve → Done** clears review readiness. Dependencies produce warnings, not status-transition locks.
- **⌘Z / ⇧⌘Z:** undo / redo. Undo merges the inverse edit against current contents, preserving independent external work; incompatible undo is refused with a diagnostic.

An example matching the specification is in [Examples/Notes.kanban.yaml](Examples/Notes.kanban.yaml).

## File safety and schema

Minimal project:

```yaml
format_version: 1
project:
  title: "Example Project"
groups: []
ungrouped:
  - id: "T-001"
    title: "Create the application skeleton"
    status: "todo"
    description: |-
      Create the initial application and document how to build it.
    acceptance_criteria:
      - "Application builds successfully"
      - "Main window opens"
    depends_on: []
    agent_notes: ""
    verification: []
    ready_for_review: false
```

`format_version: 1`, `project`, `groups`, and `ungrouped` are required. Tasks require stable, globally unique string IDs, nonempty titles, and `todo`, `doing` or `done` status. Optional task fields are `description`, `acceptance_criteria`, `depends_on`, `agent_notes`, `verification`, and `ready_for_review`.

The codec checks required types, duplicate keys and IDs, missing references, cycles, unsupported versions, custom tags, anchors and aliases. Dates and null-like text must be quoted; booleans must be `true` or `false`. Unknown fields using supported mappings, sequences, strings, decimal integers and booleans survive editing. Multiline descriptions and notes use literal blocks; other strings are quoted to preserve their types. Serialization has deterministic field order. Arbitrary comments are preserved on a no-op save but may be removed after a semantic edit.

The native document lifecycle supplies coordinated saves and standard undo integration. A lightweight 650 ms URL-based poll also detects uncoordinated shell edits and atomic replacement, using the document's own file coordinator. The poll is cancelled when the view closes. Native disk revision metadata is acknowledged after a successful read/merge, preventing redundant macOS conflict warnings. No project sidecars are created.

Before a write, the current disk document is validated and compared with the last acknowledged model. Non-conflicting field edits merge by stable IDs. Incompatible edits, delete/edit collisions and ambiguous simultaneous reordering pause saving. The conflict view displays both versions and offers **Export Local and Load External**, preserving local work in an explicitly chosen separate file. Invalid external YAML retains the last valid board and pauses edits/writes until repaired. Read/permission errors are surfaced rather than treated as missing files. Unchanged files are not normalized or rewritten merely by opening them.

File coordination cannot lock out a process that deliberately ignores it. A second byte comparison immediately before writing narrows that race, but simultaneous uncoordinated writes during the final filesystem replacement remain a platform limitation. Agents should reread before editing and use atomic replacement.

## Validation

Core tests cover schema rejection, stable round-trips, unknown-field retention, task/group ordering, review rules, dependency eligibility, three-way merging, conflicts, native staging destinations, invalid-file recovery, no-op saves, missing files and undo/redo with external edits.

Native smoke checks cover document creation/open/save, multiple windows, autosaving, atomic external reload, invalid YAML and repair, approval after external edits, undo/redo, search and keyboard navigation. The optional `taskboardUITests` target contains a basic inspector regression test.

## Implementation map

| Area | Source |
| --- | --- |
| Value model, ordering and derived progress | `taskboard/Core/Project.swift` |
| YAML validation and stable output | `taskboard/Core/YAMLCodec.swift` |
| Three-way merge | `taskboard/Core/ProjectMerge.swift` |
| Brief generation | `taskboard/Core/AgentBrief.swift` |
| Coordinated persistence and snapshots | `taskboard/Documents/ProjectFile.swift` |
| SwiftUI document, undo and recovery | `taskboard/Documents/KanbanDocument.swift` |
| Board and group management | `taskboard/ContentView.swift` |
| Inspector and native window setup | `taskboard/Views/` |

References: [project specification](Project%20Specification_%20Native%20macOS%20Kanban.md), [Apple SwiftUI Document](https://developer.apple.com/documentation/swiftui/document), [Apple WritableDocument](https://developer.apple.com/documentation/swiftui/writabledocument), [Yams](https://github.com/jpsim/Yams).
