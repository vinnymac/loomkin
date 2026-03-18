# Loom Kin — Backlog & Roadmap

> Single source of truth for planned work. Survives restarts, commits, and context loss.
> Last updated: 2025-03-18

---

## 🔥 Active Sprint: Workspace Experience Overhaul

### Layout & Proximity
- [ ] **Move user input + concierge area closer together** — currently at opposite ends of the UI. Should feel like a conversation, not shouting across a room.
- [ ] **Concierge-orchestrated feel** — interface should feel like the concierge is coordinating everything. The concierge IS the UI host.
- [ ] **Concierge UI control tools** — give the concierge agent tools to control the interface (open sidebar panels, highlight agents, push notifications, etc.)
- [ ] **Concierge leadership tools** — real-time agent activity streams, interrupt/redirect mid-task, work-in-progress inspection, conflict auto-resolution, file access guardrails (read-only vs read-write scoping per agent)
- [ ] **Kin-requested reinforcements** — kin should have a tool to request that the concierge spin up an additional kin to help them. The requesting kin specifies the role/skillset they need (e.g. "I need a researcher" or "I need a CSS specialist") and the new kin is spawned in tight communication with the requester — paired up, sharing context, collaborating directly on the same problem.
- [ ] **Work isolation principle** — new work must never block on or collide with in-progress work. If a new initiative overlaps with what a team is already doing, either: (a) queue it until they finish, or (b) spin up a separate team on a separate branch so they can't conflict. The concierge must assess overlap before assigning new work.
- [ ] **Kill switch** — concierge needs the ability to halt an entire team immediately if they're going down the wrong road. Stop all agents, revert their uncommitted changes, and reassess. This should be a single action, not dissolve + manual cleanup.

### Kin Cards & Teams
- [ ] **Kin focus cards as tabbed modals** — when you click a kin card, it opens a rich modal with tabs:
  - Activity tab (what they're doing now, recent actions)
  - Decisions tab (decisions made by this kin)
  - Files tab (files created/modified)
  - History tab (completed tasks, past work)
- [ ] **Team card grouping** — kin cards should be logically grouped by team, not a flat list
- [ ] **Kin cards show work summary** — at-a-glance view of what each agent has accomplished

### Visual Cues & Status Communication
- [ ] **Visual cues for agent state** — at-a-glance indicators showing what's happening: agent working/idle/blocked, task progress, team health. Color, animation, iconography that communicates status without reading text.
- [ ] **Activity pulse** — subtle visual indicators (glow, pulse, typing animation) showing that agents are actively working, not just sitting there

### Dynamic Sidebar
- [ ] **Sidebar for live work surfaces** — brainstorm sessions, reports, detailed results appear dynamically as they happen
- [ ] **Sidebar complements, never duplicates** — don't repeat what's already visible in the main area
- [ ] **Sidebar auto-appears** — when relevant content emerges (brainstorm starts, report ready), sidebar slides in

### Personality & Entertainment
- [ ] **Kin personality system** — agents get ridiculous human names from pop culture (book characters, TV characters, etc.)
- [ ] **In-character chat bubbles** — kin periodically make remarks in character based on what they're doing. Cute, immersive, doesn't impact work.
- [ ] **Subtle entertainment value** — the interface should be fun to watch, not just functional

---

## 🧠 System Prompts & Agent Tools

> This is foundational — everything else works better when kin have the right instructions and the concierge has the right levers.

### System Prompt Improvements
- [ ] **Research-only role enforcement** — researcher kin system prompts must prohibit file_write/file_edit. Currently "researcher" is a suggestion, not a constraint. Kin ignore boundaries.
- [ ] **Region claiming actually enforced** — system prompts tell kin to claim regions, but there's no enforcement. Conflicts happen anyway. Need hard guardrails, not polite suggestions.
- [ ] **Task focus discipline** — kin wander off-task (Builder was supposed to design backlog schema, ended up reading UI component files). Prompts need stronger "stay in your lane" instructions tied to the specific task assigned.
- [ ] **Corrective message responsiveness** — when the concierge sends a redirect/correction, kin need to actually process and respond to it. Currently messages may be ignored or arrive too late.
- [ ] **Read vs write intent** — conflict detection currently fires on reads AND writes. System needs to distinguish "agent is reading a file to understand it" from "agent is editing a file." Only the latter should trigger conflicts.

### Concierge Tool Additions
- [ ] **Inspect agent activity** — tool to see what an agent is currently doing (last N tool calls, current file, thinking state)
- [ ] **Redirect agent** — tool to interrupt an agent mid-task and give them new instructions without dissolving the whole team
- [ ] **Scope agent file access** — tool to set per-agent file boundaries (read-only dirs, write-allowed dirs)
- [ ] **Kill team with revert** — dissolve team + git checkout on all uncommitted changes they made. One action.
- [ ] **Kin reinforcement request tool** — kin-facing tool that sends a structured request to the concierge: "I need a [role] to help me with [problem]." Concierge can approve/deny and spawn the paired kin.
- [ ] **Branch isolation tool** — spin up a team on a fresh git branch so they can't conflict with main working tree

### Agent Tool Review
- [ ] **Audit existing kin tools** — catalog every tool available to each role. Are there tools kin have that they shouldn't? Tools they need but don't have?
- [ ] **Role-specific tool filtering** — researchers shouldn't have file_write. Reviewers shouldn't have file_edit. Tools should be filtered by role at spawn time.
- [ ] **Task-scoped tool context** — when a kin picks up a task, their tool access should reflect the task scope (e.g., "you may only read files in lib/loomkin_web/" for a UI research task)

---

## 📋 Infrastructure & Reliability

### Context & Memory
- [ ] **Fix keeper negativity bias** — keepers currently only store failure logs. Need auto-offload hooks for positive work products (research results, design decisions, implementation summaries).
- [ ] **Proper backlog system** ✅ (this file!)
- [ ] **Data persistence** — task results, conversation synthesis, and keeper data must survive restarts

### Long-Horizon Autonomy
- [ ] **Review Epic-16** (docs/epic-16-long-horizon-coding.md) — evaluate long-horizon coding patterns for adoption
- [ ] **Solve Vertex AI quota exhaustion** — multi-agent teams burn through quota. Need rate limiting or model rotation.
- [ ] **Agent context recovery** — when agents restart, they should be able to resume work from keepers/backlog

---

## 🧊 Icebox (Future Ideas)
- [ ] Decision graph cleanup — prune the 47 stale goals, or deprecate the graph in favor of this backlog
- [ ] Agent effectiveness metrics — track task completion rates, artifact production
- [ ] Cross-team collaboration improvements

---

## ✅ Completed
_(Move items here when done)_

