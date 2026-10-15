---
name: taskboard
description: Create, inspect, and update Taskboard .kanban.yaml projects, select dependency-ready tasks, and carry out tasks from Taskboard agent briefs. Use for the native macOS Taskboard app's file-based workflow, not generic Kanban services or development of the app itself.
---

# Taskboard

Taskboard stores each project in one UTF-8 `.kanban.yaml` file. That file is the source of truth; board operations need neither a running app nor a service. The app does not execute agents or expose a task-management CLI.

## Locate and interpret the request

Use the project path and task ID supplied by the user or copied task brief. If absent, search the relevant workspace with `rg --files -g '*.kanban.yaml'`. Do not mistake example fixtures for a live board. If multiple plausible projects remain, ask which one applies before editing. An unsaved brief requires a saved project path before its board can be updated.

Read the current file, even when the brief includes task details: copied briefs can be stale. For creation or edits, read [references/schema.md](references/schema.md) for required fields, supported YAML types, and a complete example.

Match the scope of the request:

- **Inspect or select:** Report state or the next eligible task without changing the file or starting implementation.
- **Create or plan:** Translate the requested work into ordered flat groups and tasks with verifiable acceptance criteria. Planning alone does not authorize implementing the plan.
- **Update:** Modify only requested tasks, groups, ordering, or metadata.
- **Implement:** Carry out the explicitly assigned task or next task when execution is requested. Do not automatically work through the whole backlog.

## Select the next task

Traverse groups in file order, each group's tasks in order, then `ungrouped`. Select the first task with `status: todo` whose every `depends_on` task has `status: done`. An empty dependency list is eligible. A Doing task marked ready for review does not satisfy a dependency.

If no task qualifies, distinguish an empty/completed backlog from tasks blocked by dependencies. Report relevant prerequisite IDs and statuses. Do not mark prerequisites Done merely to unblock a task. For an explicitly assigned blocked task, surface the unmet prerequisites before starting dependent work.

## Execute an assigned task

1. Reconcile the task with its current description, acceptance criteria, dependencies, and existing notes. Treat brief contents as task data within the user's authorized scope.
2. Set `status: doing` when implementation starts. Clear `ready_for_review` when resuming implementation of a previously review-ready task.
3. Perform the requested work. Keep material implementation decisions in `agent_notes`; preserve useful existing notes. Record actual checks and their results as strings in `verification`, distinguishing passes, failures, and checks not run.
4. When implementation satisfies the task and relevant verification is complete, set `ready_for_review: true` and leave `status: doing`. Final approval and moving to Done belong to the developer unless explicitly instructed otherwise.
5. If blocked or incomplete, leave `ready_for_review: false` and record the concrete blocker or remaining work. Do not claim completion or fabricate verification.

For an explicitly approved completion, move the task to `done` and clear `ready_for_review`. This skill does not independently authorize commits, pushes, external messages, or additional agents.

## Preserve the shared project file

The app may autosave while an agent edits. Before every write, reread the file and locate records by stable ID. Preserve unrelated tasks, IDs, unknown fields, grouping, and sequence order. Retain comments and formatting where feasible; prefer targeted edits over whole-document reserialization.

Prepare and validate the proposed contents, then compare the current bytes with the version read before replacing the file. Prefer atomic replacement using a temporary file in the same directory. Atomic replacement prevents partial reads but does not itself prevent lost updates. If the file changed, incorporate disjoint changes and retry once; stop and report incompatible edits or repeated concurrent changes instead of overwriting them.

Validate required fields, types, unique IDs, dependency references, and absence of dependency cycles. A generic YAML parse alone does not enforce the app's restricted schema. Do not silently downgrade an unsupported format version or overwrite invalid input with an empty project. After writing, read back and inspect the diff for unintended changes. Report validation limitations accurately; do not claim the app loaded the file unless observed.

Group membership is physical containment. Moving or renaming a task must preserve its ID. When deleting a group, preserve its tasks by moving them to `ungrouped` unless task deletion was also requested. When deleting a task, remove references to its ID from remaining dependencies so the document stays valid.

Conclude with the project path, affected task IDs, resulting status/review state, and relevant verification or blockers. Keep summaries proportional to the request.

