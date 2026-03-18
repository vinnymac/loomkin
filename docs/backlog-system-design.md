# Backlog System Design

> A DB-backed persistent backlog/roadmap that replaces markdown files and the noisy
> decision graph for tracking planned work. Agents can create, query, and update items
> via tools. The concierge manages and presents the backlog to users.

## Problem

The decision graph has 47+ stale "active" goals with no prioritization, no cleanup
mechanism, and no distinction between "active sprint work" and "someday ideas." The
current `docs/backlog.md` file is better organized but isn't queryable by agents,
doesn't survive semantic loss, and can't be updated programmatically.

**What we need:**
- Persistent, DB-backed storage that survives restarts
- Prioritized, status-tracked items with lifecycle states
- Agent tools for CRUD + querying
- Workspace-scoped (supports multi-tenant)
- Concierge as primary interface — the concierge curates and presents the backlog

## Design Decisions

### 1. Separate from Decision Graph — Complementary, Not Replacement

The decision graph captures *reasoning* (how agents think, what they deliberated).
The backlog captures *planned work* (what to do, in what order). They serve different
purposes:

| Aspect | Decision Graph | Backlog |
|--------|---------------|---------|
| Purpose | Audit trail of reasoning | Work tracking |
| Lifecycle | Append-only, grows forever | Curated, items move to done/cancelled |
| Granularity | Per-agent, per-decision | Per-feature/task/bug |
| Primary user | Agent introspection | Concierge + human |
| Query pattern | "Why did we do X?" | "What should we do next?" |

A backlog item can link to a decision node via `decision_node_id` for traceability.

### 2. Epic-16 Scope Awareness

Each backlog item includes a `scope_estimate` field aligned with Epic-16's tier system:

- **quick** — ~1-3 files, isolated change, low coupling
- **session** — ~4-15 files, moderate coupling, multiple modules
- **campaign** — 15+ files, cross-module, new deps, many tests

This lets the concierge estimate effort and set expectations when presenting work
to the user.

### 3. Status Lifecycle

```
  icebox → todo → in_progress → done
             ↘ blocked ↗         ↘ cancelled
```

- **icebox** — parked ideas, not ready for work
- **todo** — ready for work, prioritized
- **in_progress** — currently being worked on
- **done** — completed with optional result summary
- **blocked** — waiting on a dependency or decision
- **cancelled** — decided not to do

### 4. Priority Scale

1 = critical (do now), 2 = high, 3 = medium (default), 4 = low, 5 = someday/maybe

## Schema

**File:** `lib/loomkin/schemas/backlog_item.ex`

```elixir
schema "backlog_items" do
  field :title, :string
  field :description, :string
  field :status, Ecto.Enum, values: [:icebox, :todo, :in_progress, :done, :blocked, :cancelled]
  field :priority, :integer, default: 3        # 1-5
  field :category, :string                      # e.g. "ui", "infra", "bugfix"
  field :epic, :string                          # e.g. "workspace-overhaul"
  field :tags, {:array, :string}, default: []
  field :created_by, :string                    # agent name
  field :assigned_to, :string                   # agent name
  field :assigned_team, :string                 # team ID
  field :depends_on_id, :binary_id              # another backlog item
  field :acceptance_criteria, {:array, :string}
  field :result, :string                        # set when done
  field :scope_estimate, Ecto.Enum, values: [:quick, :session, :campaign]
  field :sort_order, :integer, default: 0       # within priority band
  field :session_id, :binary_id                 # which session created it
  field :decision_node_id, :binary_id           # link to decision graph
  belongs_to :workspace, Loomkin.Workspace
  timestamps(type: :utc_datetime)
end
```

**Indexes:**
- `(status, priority)` — primary query path for actionable items
- `(category)` — filter by category
- `(epic)` — roadmap grouping
- `(workspace_id)` — workspace scoping
- `(assigned_team)` — team-specific views
- `(depends_on_id)` — dependency lookup

## Context Module

**File:** `lib/loomkin/backlog.ex`

### Core Operations
- `create_item(attrs)` — create a new backlog item
- `get_item(id)` — fetch by ID
- `update_item(id, attrs)` — update fields
- `delete_item(id)` — remove an item

### Query Patterns
- `list_actionable(opts)` — todo + in_progress sorted by priority (concierge's main view)
- `list_by_status(status, opts)` — filter by lifecycle state
- `list_by_epic(opts)` — roadmap view grouped by epic
- `list_by_category(category, opts)` — filter by category
- `list_by_team(team_id, opts)` — items assigned to a specific team
- `search(term, opts)` — full-text search across title + description
- `get_summary(opts)` — counts by status for dashboard display

### Status Transitions
- `start_item(id)` — move to in_progress
- `complete_item(id, result)` — mark done with result
- `block_item(id)` — mark blocked
- `cancel_item(id)` — mark cancelled
- `icebox_item(id)` — send to icebox
- `reprioritize(id, priority)` — change priority

### Migration from Decision Graph
- `import_from_decision_graph(opts)` — one-time import of active goals as backlog items

## Agent Tools

Three tools registered in `Loomkin.Tools.Registry` (solo tools, available to all agents):

### 1. `create_backlog_item`
**File:** `lib/loomkin/tools/create_backlog_item.ex`

Creates a new backlog item. Parameters:
- `title` (required) — short title
- `description` — detailed description
- `priority` — 1-5 (default 3)
- `status` — initial status (default "todo")
- `category` — grouping category
- `epic` — roadmap epic name
- `tags` — list of tag strings
- `scope_estimate` — "quick", "session", or "campaign"
- `depends_on_id` — ID of dependency

### 2. `query_backlog`
**File:** `lib/loomkin/tools/query_backlog.ex`

Queries the backlog with multiple modes:
- `actionable` — what to work on next
- `by_status` — filter by status
- `by_epic` — roadmap view
- `by_category` — filter by category
- `by_team` — team-specific items
- `search` — full-text search
- `summary` — counts overview

### 3. `update_backlog_item`
**File:** `lib/loomkin/tools/update_backlog_item.ex`

Updates any field on a backlog item:
- `item_id` (required) — which item
- `status` — new lifecycle state
- `priority` — new priority
- `result` — completion summary
- `assigned_to` — agent assignment
- `assigned_team` — team assignment
- Any other field

## UI Integration Plan

The backlog surfaces in the workspace through the concierge:

### Concierge as Curator
The concierge agent should:
1. Query the backlog at session start to know what's planned
2. Present actionable items to the user when asked "what should we work on?"
3. Create backlog items from user requests that aren't immediate
4. Update item status as work progresses
5. Import stale decision graph goals on first use

### Workspace Status Strip
Task progress from the backlog can feed into the workspace status strip:
```
3/12 tasks done | 5 agents | $2.40
```

### Future: Dedicated Backlog Panel
A sidebar panel or modal that shows:
- Kanban-style columns (todo → in_progress → done)
- Grouped by epic for roadmap view
- Drag-to-reprioritize
- One-click status transitions

This is a separate UI task — the data layer is ready now.

## Migration

**File:** `priv/repo/migrations/20260318060000_create_backlog_items.exs`

Creates the `backlog_items` table with all fields and indexes. Self-referencing
foreign key for `depends_on_id` (nilified on delete). Workspace foreign key
with nilify-on-delete.

## Files Created/Modified

| File | Action |
|------|--------|
| `lib/loomkin/schemas/backlog_item.ex` | Created — Ecto schema |
| `lib/loomkin/backlog.ex` | Created — context module with CRUD + queries |
| `lib/loomkin/tools/create_backlog_item.ex` | Created — agent tool |
| `lib/loomkin/tools/query_backlog.ex` | Created — agent tool |
| `lib/loomkin/tools/update_backlog_item.ex` | Created — agent tool |
| `lib/loomkin/tools/registry.ex` | Modified — registered 3 new tools + param keys |
| `priv/repo/migrations/20260318060000_create_backlog_items.exs` | Created — DB migration |
| `docs/backlog-system-design.md` | Created — this document |

## How It Replaces the Decision Graph for Work Tracking

| Before | After |
|--------|-------|
| 47 stale "active" goals | Curated backlog with explicit lifecycle |
| No prioritization | Priority 1-5 with sort order |
| No cleanup mechanism | Items move to done/cancelled |
| Goals mixed with reasoning nodes | Clean separation: backlog = work, graph = reasoning |
| File-based backlog (docs/backlog.md) | DB-backed, queryable by agents |
| Not accessible to agents | Three dedicated tools |
| No scope estimation | Epic-16 scope tiers (quick/session/campaign) |

The decision graph is NOT removed — it continues to serve its purpose as an
audit trail of agent reasoning. The backlog adds the missing "work management"
layer on top.
