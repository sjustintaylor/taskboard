**Working name:** Taskboard\
**Platform:** macOS\
**Language:** Swift / SwiftUI\
**Architecture:** Local-first, document-based application\
**Storage:** One human-readable YAML file per project\
**Primary users:** Software developers working with AI coding agents

## 1. Product overview

Taskboard is a lightweight native macOS Kanban application designed to help software developers plan, supervise, and track work performed by AI coding agents.

Its central design principle is that **the project file is the single source of truth**. Both the developer and an external AI coding agent can read and modify the same file.

The application provides a visual interface for managing tasks, organising work into epics or phases, and monitoring implementation progress.

### Design principles

- **File-first:** No database, cloud account, or proprietary storage.

- **Agent-friendly:** Project files are easy for LLMs to read, understand, and modify.

- **Human-supervised:** AI agents implement work; developers retain visibility and control.

- **Minimal:** Three workflow states, without the complexity of conventional project management software.

- **Native:** Standard macOS document handling, keyboard shortcuts, drag-and-drop, and system integration.

- **Git-compatible:** Project files can live alongside source code and be committed to version control.

## 2. Core product decisions

| <p>Area</p> | <p>Decision</p> |
| - | - |
| Task states | Todo, Doing, Done |
| Task grouping | Named, ordered epics or phases |
| Group hierarchy | Single level; no nested groups |
| File format | YAML (`.kanban.yaml`) |
| Storage model | One file per project |
| Agent integration | Direct file access, no API required |
| Progress tracking | Task counts, group completion, active work |
| Completion approval | Developer review by default |
| AI execution | External coding tools, not embedded |
| Connectivity | Fully offline |

**Recommended interface:** Todo displays collapsible groups, while Doing and Done display flat lists with group labels. This preserves a simple three-column board without losing the organisational structure of larger projects.

## 3. Functional requirements

### 3.1 Project documents

The application must support:

- Creating a new project document.

- Opening an existing project document through Finder or File > Open.

- Opening multiple projects in separate windows.

- Automatic saving of changes.

- Reloading when an external process modifies the project file.

- Displaying the current file location and opening its containing folder in Finder.

- Undo and redo of changes made within the application.

Each project must be completely represented by one ordinary text file. No database, sidecar files, or hidden application-specific project directory is required.

### 3.2 Kanban board

The primary interface displays three columns:

**Todo**

- Contains tasks not yet started.

- Tasks are displayed within collapsible, ordered groups.

- Each group shows its name, task count, and completion progress.

- An Ungrouped section contains tasks without a group.

**Doing**

- Displays tasks currently being implemented.

- Tasks include a visible label identifying their group.

- Tasks ready for developer review are visually distinguished.

**Done**

- Contains completed, reviewed tasks.

- Tasks retain their original group association.

- Completed tasks display a concise implementation summary where available.

Tasks can be moved between columns through drag-and-drop or a context menu. Reordering within columns is also supported.

Changes must be reflected immediately in the underlying document.

### 3.3 Groups: epics and phases

Groups provide a lightweight mechanism for organising the project backlog.

Supported operations:

- Create, rename, delete, and reorder groups.

- Collapse and expand individual groups.

- Move tasks between groups through drag-and-drop.

- Create tasks directly inside a group.

- Move multiple selected tasks to another group.

- Filter the board to a particular group.

- Display completion progress per group.

Groups are flat rather than hierarchical. A group may represent an epic, development phase, feature area, or other arbitrary collection of tasks.

Deleting a group must not delete its tasks. Tasks are moved to Ungrouped after confirmation.

**Progress calculation:** A group's completion percentage is the number of Done tasks divided by the total number of tasks belonging to that group, regardless of which column currently displays them.

### 3.4 Tasks

Each task has the following properties.

| <p>Property</p> | <p>Required</p> | <p>Description</p> |
| - | - | - |
| `id` | Yes | Stable, unique task identifier |
| `title` | Yes | Short task description |
| `status` | Yes | `todo`, `doing`, or `done` |
| `description` | No | Markdown-compatible implementation instructions |
| `acceptance_criteria` | No | List of verifiable completion conditions |
| `depends_on` | No | References to other task IDs |
| `agent_notes` | No | Implementation progress and decisions reported by the agent |
| `verification` | No | Tests run and their results |
| `ready_for_review` | No | Flag indicating the agent has finished implementation |

Tasks belong to at most one group.

The UI uses a compact task card for ordinary navigation. Selecting a task opens a detail inspector with editable fields.

Task descriptions and notes support Markdown text, including code fragments.

Task IDs must remain stable when tasks are renamed, moved, or reordered.

### 3.5 Developer review workflow

The application distinguishes implementation progress from developer approval without introducing a fourth Kanban column.

1. A developer creates a task in Todo.

2. The task is selected for implementation and moves to Doing.

3. An external AI agent implements the task.

4. The agent updates its implementation notes, verification results, and `ready_for_review` flag in the project file.

5. The task remains in Doing, but becomes visually marked as ready for review.

6. The developer reviews the implementation and moves the task to Done, or returns it to active work.

Moving a task to Done through the application clears `ready_for_review`.

The application should warn when unresolved dependencies exist, but should not impose a complex workflow engine.

### 3.6 Agent integration

The MVP must work with coding agents that can access and edit ordinary files. There is no requirement for direct integration with a specific AI provider or agent SDK.

**Agent task brief**

Each task offers a Copy Task Brief action. This generates an instruction containing:

- Project and task identification.

- Task description and acceptance criteria.

- Relevant dependencies.

- The project file path.

- Instructions for updating progress in the project file.

- Instructions to report implementation changes and verification results.

The project toolbar also offers Copy Next Task Brief, selecting the first eligible Todo task in group and task order whose dependencies are Done.

An agent can update the project without using the application's UI.

**Agent editing contract**

An external agent must:

- Read the current project file before editing it.

- Preserve existing IDs and unrelated tasks.

- Modify only fields required for its work.

- Keep the file syntactically valid.

- Move the selected task to Doing when work starts.

- Record material progress and verification outcomes.

- Mark `ready_for_review: true` when implementation is ready.

- Leave final approval to the developer unless explicitly instructed otherwise.

Agent instructions are generated on demand. They do not require another persistent file.

## 4. Document format

### 4.1 Format selection

Use UTF-8 YAML with the file extension `.kanban.yaml`.

YAML is selected because it is readable without the application, supported by common AI coding tools, and suitable for representing both structured metadata and multiline natural-language instructions.

The format must use a deliberately restricted subset of YAML:

- No custom YAML tags.

- No anchors or aliases.

- No executable content.

- No implicit dates or application-specific scalar types.

- Explicit string, integer, boolean, and sequence fields.

- Consistent formatting and stable field order when the application serialises documents.

Descriptions use YAML literal block strings to minimise escaping.

### 4.2 Document structure

The top-level structure contains:

- `format_version`: Integer document schema version.

- `project`: Project title and optional description.

- `groups`: Ordered sequence of groups, each containing an ordered task sequence.

- `ungrouped`: Ordered sequence of tasks without a group.

Group IDs are stable. Group and task ordering is determined by their position in the YAML sequences, rather than separate numeric sort fields.

The format supports moving tasks between groups, moving tasks between workflow states, and reordering tasks without changing their identity.

Group progress is derived dynamically and is not stored.

### 4.3 Validation

The document parser must validate:

- Supported format version.

- Uniqueness of task and group IDs.

- Valid status values.

- Required fields and field types.

- References to existing tasks in `depends_on`.

- Absence of circular task dependencies.

- Valid group/task structure.

Invalid documents must produce useful diagnostics without destroying their contents.

Unknown schema fields should be retained where practical. The application must never silently reinterpret an unsupported schema version.

### 4.4 Source-control compatibility

Project files should be suitable for storing directly in a Git repository.

Requirements:

- Stable serialisation.

- Human-readable diffs.

- No machine-specific absolute paths in the saved schema.

- No volatile timestamps added solely because a document was opened.

- No rewriting of the file when its semantic contents have not changed.

- No dependence on Git to operate.

YAML comments are not part of the document schema. Exact retention of arbitrary comments is not required in the MVP, but application-generated changes should minimise unrelated formatting changes.

## 5. User interface

### 5.1 Main window

The main window consists of:

**Toolbar**

- Project title.

- New Task button.

- Group filter.

- Search.

- Copy Next Task Brief action.

**Board**

- Three resizable or horizontally scrollable Kanban columns.

- Collapsible group sections within Todo.

- Compact cards displaying titles and relevant status indicators.

- Group progress shown inline with group headings.

**Task inspector**

- Opens on the right when a task is selected.

- Contains title, group, status, description, acceptance criteria, dependencies, agent notes, and verification results.

- Provides Copy Task Brief and review actions.

- Closes without obscuring the board.

The design should follow native macOS interaction conventions, with restrained visual styling and minimal permanent UI chrome.

### 5.2 Keyboard navigation

Minimum keyboard support:

- `⌘N`: New project.

- `⌘O`: Open project.

- `⌘F`: Search tasks.

- `⌘Z` / `⇧⌘Z`: Undo / redo.

- `Escape`: Close task inspector or cancel an operation.

- Arrow keys: Navigate task selection.

- `Return`: Open or edit selected task.

Additional shortcuts may be introduced for task creation and movement, provided they do not conflict with standard macOS shortcuts.

### 5.3 Task cards

Cards should be visually lightweight.

Default card contents:

- Task title.

- Optional abbreviated task ID.

- Group label in Doing and Done.

- Review indicator where appropriate.

- Small dependency warning when applicable.

Descriptions, acceptance criteria, and implementation notes are omitted from the card unless a compact preview is useful.

### 5.4 Progress overview

The interface displays:

- Overall tasks completed / total.

- Number of active Doing tasks.

- Number of tasks awaiting review.

- Group-level completion percentages.

The initial implementation does not need burndown charts, velocity metrics, effort estimates, or time tracking.

## 6. File synchronisation

External modification is a core use case, not an exceptional circumstance.

The application must detect changes made by editors, shell scripts, and AI coding agents, including atomic file replacement.

### Required behaviour

- Reload the document when its on-disk contents change.

- Update the board without reopening the project.

- Preserve selection and expanded/collapsed group state where possible.

- Avoid responding to the application's own writes as unrelated external changes.

- Prevent outdated in-memory state from silently overwriting new external edits.

### Conflict handling

When both the application and an external process have changed the document:

1. Compare the on-disk contents with the last acknowledged version.

2. Automatically incorporate non-conflicting changes where safely identifiable by stable task/group IDs.

3. Present a conflict resolution interface when the same content has been modified incompatibly.

4. Never silently discard either version.

The MVP may use a conservative conflict dialog rather than a full graphical merge editor.

If an external edit temporarily creates invalid YAML, the application retains the last valid in-memory snapshot, displays a parse error, and prevents writes that could overwrite the invalid file. Reloading resumes once the external file becomes valid.

## 7. Technical architecture

### 7.1 Technology

| <p>Component</p> | <p>Technology</p> |
| - | - |
| Application | Swift |
| UI | SwiftUI |
| Native integration | AppKit / Foundation where needed |
| Document management | SwiftUI document infrastructure |
| YAML | Yams |
| Concurrency | Swift concurrency |
| Persistence | Direct filesystem |
| Database | None |
| Networking | None required |

Target a current, supported macOS release. Select the document API according to the final deployment target, preferring Apple's newer `Document` model where supported.

### 7.2 Suggested modules

**Document Model**

Defines Project, Group, Task, TaskStatus, and document versioning. Contains no UI dependencies.

**YAML Codec**

Handles parsing, serialisation, and schema validation. Produces actionable parse errors.

**Document Controller**

Manages loading, saving, dirty state, filesystem change detection, and conflict resolution.

**Board State**

Derives visible tasks, group progress, review counts, ordering, filtering, and next-task eligibility.

**Board UI**

Contains the main window, three-column layout, grouped Todo sections, task cards, and inspector.

**Agent Instructions**

Generates task briefs and workflow instructions from the current document model.

### 7.3 Persistence requirements

Document writes should be atomic, coordinated with macOS document handling, and checked against the last observed disk version.

The application must support standard filesystem permissions and work with project files stored inside source repositories.

Temporary write files must not become permanent project artifacts.

UI state such as inspector visibility and collapsed groups may be maintained in application preferences rather than in the project file. These preferences must never affect the authoritative task data.

## 8. MVP scope

### Required for v1

- Document creation and opening.

- YAML parsing and writing.

- Three-column Kanban board.

- Group creation, renaming, ordering, and collapsing.

- Task CRUD operations.

- Task drag-and-drop and reordering.

- Task detail inspector.

- Acceptance criteria and agent notes.

- Review-ready indicator.

- Group and overall progress.

- Copy Task Brief.

- External file change detection.

- Safe saving and basic conflict resolution.

- Keyboard navigation.

### Explicitly excluded from v1

- Embedded LLM chat.

- Launching or controlling agent processes.

- Provider-specific API integrations.

- Multiple users or synchronised collaboration.

- Cloud project management.

- Time tracking and estimates.

- Nested groups.

- Task subtasks.

- Attachments or embedded images.

- Notifications and background task scheduling.

- Multiple project files combined into one board.

## 9. Acceptance criteria

The MVP is considered complete when:

1. A new project can be created and saved as one valid YAML file.

2. The project file can be read and edited by an ordinary text editor or AI coding agent.

3. Changes made outside the application appear on the board without manually reopening the file.

4. A project can contain multiple ordered groups and ungrouped tasks.

5. Tasks can be moved between Todo, Doing, and Done without losing their group association or metadata.

6. Tasks and groups can be reordered and retain their order across application restarts.

7. Group completion figures reflect tasks in all three workflow states.

8. An agent can update progress notes, verification results, and review readiness without using the UI.

9. The application generates a usable implementation brief for a selected task.

10. Invalid YAML produces an actionable error without data loss.

11. Concurrent external changes are not silently overwritten.

12. An unchanged document is not unnecessarily rewritten.

13. Undo and redo work for supported UI edits.

14. The application operates without internet access or user accounts.

## 10. Suggested implementation sequence

**Milestone 1 — Document foundation**

Implement the schema, model, parser, validation, serializer, and document lifecycle. Establish round-trip tests.

**Milestone 2 — Basic board**

Build the three columns, task cards, inspector, task editing, status transitions, and undo support.

**Milestone 3 — Group management**

Add ordered collapsible groups, group editing, task reassignment, filtering, and progress counts.

**Milestone 4 — Agent workflow**

Add task brief generation, agent notes, dependency awareness, verification records, and ready-for-review indicators.

**Milestone 5 — External file reliability**

Implement external change handling, conflict protection, invalid-file recovery, and integration tests using simulated agent edits.

**Milestone 6 — Native UX polish**

Complete keyboard navigation, accessibility, empty states, drag-and-drop refinements, and document usability testing.

## 11. Example project file

The following represents a complete project with two phases, three tasks, and one task awaiting developer review.

```

format_version: 1

project:
  title: Notes Application
  description: |-
    A lightweight native macOS notes application.

groups:
  - id: foundation
    title: Foundation
    description: Core application infrastructure.

    tasks:
      - id: T-001
        title: Create application skeleton
        status: done
        description: |-
          Create the initial SwiftUI application.
        acceptance_criteria:
          - Application builds successfully
          - Main window opens
        depends_on: []
        agent_notes: |-
          Created SwiftUI application target.
        verification:
          - "xcodebuild: passed"
        ready_for_review: false

      - id: T-002
        title: Implement document persistence
        status: doing
        description: |-
          Create a Codable document model and support
          saving notes to individual Markdown files.
        acceptance_criteria:
          - Notes can be saved
          - Notes can be reopened
          - Existing notes are not overwritten
        depends_on:
          - T-001
        agent_notes: |-
          Persistence implemented. Unit tests pass.
          Ready for developer review.
        verification:
          - "Unit tests: passed"
        ready_for_review: true

  - id: interface
    title: User Interface
    description: Build the note editing experience.

    tasks:
      - id: T-003
        title: Implement notes list
        status: todo
        description: |-
          Display available notes in a sidebar.
        acceptance_criteria:
          - Notes appear in a list
          - Selecting a note opens the editor
        depends_on:
          - T-002
        agent_notes: ""
        verification: []
        ready_for_review: false

ungrouped: []

```

## 12. Conceptual interface

**Notes Application**

Project progress

1 / 3

Todo 1

Foundation

User Interface

Implement notes list

T-003

Add task

Doing 1

Implement document persistence

Foundation

Review ready

Done 1

Create application skeleton

Foundation

Conceptual layout, illustrating grouped Todo tasks and a review-ready task in Doing.

## Technical references

The proposed stack is supported by existing native tooling. Apple's newer SwiftUI document APIs provide document reading/writing infrastructure, while Yams supports Codable-style YAML parsing and encoding. External file coordination requires special attention because not all command-line writes participate in macOS file coordination.

- [Apple — SwiftUI Documents](https://developer.apple.com/documentation/swiftui/documents)

- [Apple — NSFilePresenter](https://developer.apple.com/documentation/foundation/nsfilepresenter)

- [Yams — Swift YAML parser](https://github.com/jpsim/Yams?utm_source=chatgpt.com)

**Key architectural recommendation:** Keep the application separate from the AI coding agent. The YAML document should define the work and its current state; the Swift application should visualise, edit, validate, and protect that state. This makes the tool usable with existing and future coding agents without provider-specific integration.
