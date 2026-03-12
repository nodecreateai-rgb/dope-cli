# Local Long Memory Architecture

## Why

通用聊天记忆很容易在多任务/多会话场景里串味。
这个方案的目标不是“更像人”，而是“更像可靠的本地状态系统”。

## Core ideas

1. SQLite as source of truth
2. FTS5 for fast lexical retrieval
3. Facts / task_state / summaries separated
4. Query is always scoped when possible
5. Summary is cache, not truth

## Storage

Single SQLite database:

- `facts`
- `task_state`
- `summaries`

Each row includes:

- source
- session_key
- task_id
- scope
- confidence
- created_at
- updated_at
- supersedes

## Query path

1. exact scope filter (task/session/scope)
2. FTS retrieval
3. sort by recency + confidence
4. return structured rows, not only prose

## Accuracy strategy

- facts are written separately from summaries
- task states are isolated by task_id
- summaries never overwrite facts
- future conflict detection can compare rows with same key/task_id

## Why this is fast

- SQLite local file
- FTS5 in-process
- no network
- no embedding model in MVP
- explicit scopes reduce search space
