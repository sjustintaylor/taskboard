# Taskboard project format, version 1

This describes the native Taskboard app's file contract. Source: [YAMLCodec.swift](https://github.com/sjustintaylor/taskboard/blob/main/taskboard/Core/YAMLCodec.swift) and [AgentBrief.swift](https://github.com/sjustintaylor/taskboard/blob/main/taskboard/Core/AgentBrief.swift). Consult matching app source if a future format changes; never silently convert an unsupported version.

## Fields

| Location | Required | Optional |
| --- | --- | --- |
| Root | `format_version` integer `1`; `project` mapping; `groups` sequence; `ungrouped` task sequence | Unknown fields preserved |
| `project` | `title`: nonempty string | `description`: string |
| Each group | `id`, `title`: nonempty strings; `tasks`: task sequence | `description`: string |
| Each task | `id`, `title`: nonempty strings; `status`: `todo`, `doing`, `review`, or `done` | `description`, `agent_notes`: strings; `acceptance_criteria`, `depends_on`, `verification`: sequences of strings; `ready_for_review`: boolean |

Group IDs must be unique among groups. Task IDs must be unique across all groups and `ungrouped`. Follow existing ID conventions when creating records; never renumber existing IDs. Every dependency must reference an existing task ID, with no cycles (including self-dependencies).

Group and task sequence positions define ordering. Groups are flat, and tasks belong to their containing group or `ungrouped`; there is no required `group_id` or numeric sort field. Optional fields may be omitted. Required empty sequences must be `[]`, never null.

Unknown fields at any mapping level must survive edits and use supported value types. Do not add machine-specific absolute paths or timestamps as new task metadata; the copied brief can carry the absolute project path separately.

## YAML constraints

Use UTF-8 with string-key mappings, sequences, strings, decimal integers, and literal `true`/`false` booleans. Do not introduce tags, anchors, aliases, nulls, floats, or implicitly typed dates. Duplicate mapping keys are invalid. Quote text resembling numbers, booleans, dates, or nulls; double-quote ordinary text and use literal blocks for multiline prose. Avoid serializers that introduce aliases or change string types.

## Complete example

```yaml
format_version: 1
project:
  title: "Example project"
  description: |-
    A small implementation plan.
groups:
  - id: "foundation"
    title: "Foundation"
    description: "Core behavior"
    tasks:
      - id: "T-001"
        title: "Define the storage model"
        status: "todo"
        description: |-
          Implement the model described in the project requirements.
        acceptance_criteria:
          - "Required fields survive a save and reload."
        depends_on: []
        agent_notes: ""
        verification: []
        ready_for_review: false
ungrouped:
  - id: "T-002"
    title: "Verify storage round trips"
    status: "todo"
    acceptance_criteria:
      - "A test covers saving and reloading representative project data."
    depends_on:
      - "T-001"
```

The next eligible task in this example is `T-001`. `T-002` remains blocked until `T-001` is Done, including while `T-001` is in Review. Legacy `status: doing` with `ready_for_review: true` also appears in Review. Use `status: review` for new review handoffs; clear the legacy flag when returning to Doing or moving to Done.
