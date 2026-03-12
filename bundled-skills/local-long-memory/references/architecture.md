# Local Long Memory Architecture

## Why

通用聊天记忆很容易在多任务/多会话场景里串味。
这个方案的目标不是“更像人”，而是“更像可靠的本地状态系统”。

## Core ideas

1. SQLite as source of truth
2. FTS5 for fast lexical retrieval
3. Facts / task_state / events / summaries separated
4. Query is always scoped when possible
5. Summary is cache, not truth
6. High-confidence data is written immediately; summaries are finalized later
7. Retrieval should happen before a run via a small injected bundle, not by dumping the whole DB into context

## Storage

Single SQLite database:

- `facts`
- `task_state`
- `events`
- `summaries`

Each row includes:

- source
- session_key
- task_id
- scope
- confidence
- created_at
- updated_at
- supersedes (where applicable)

## Query path

### write path
- validated facts -> immediate fact/task/event writes
- unstable or aggregate understanding -> summary/finalize later

### read path
1. derive query basis from recent user text
2. infer possible `task_id`
3. exact scope filter (`task_id`, `session_key`, `scope`) first
4. FTS retrieval second
5. sort by recency + confidence
6. inject only a small memory bundle into the current run

## Accuracy strategy

- facts are written separately from summaries
- task states are isolated by task_id
- events capture per-conversation validated milestones
- summaries never overwrite facts
- future conflict detection can compare rows with same key/task_id

## Runtime integration

Recommended runtime integration is an `agent:bootstrap` hook:

- read current session file
- extract the last few user messages
- generate a narrow query basis
- recall session/task scoped rows first
- build a small markdown bundle
- append that bundle to injected `MEMORY.md`

This keeps the experience fast and automatic without bloating prompt context.

## Why this stays fast

- SQLite local file
- FTS5 in-process
- no network
- no embedding model in MVP
- exact scope filters reduce search space before FTS
- indexes on task/session/scope/updated_at
- injected bundle stays small

## Operational rule

Default retrieval should be:
- task-scoped when task exists
- session-scoped when session context exists
- global only when necessary

This is a hard performance and accuracy rule, not just a suggestion.
