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

## Write path

### message:preprocessed
Not every message should be persisted.

Persist only high-signal items such as:
- explicit remember/preference/default/rule statements
- verified success/failure results
- reusable agreements or conventions

These become:
- `facts`
- `events`

### session:compact:after
Use compaction boundaries to persist:
- stage summaries
- task summaries
- compressed session understanding

These become:
- `summaries`

## Read path

1. derive query basis from recent user text
2. infer possible `task_id`
3. exact scope filter (`task_id`, `session_key`, `scope`) first
4. FTS retrieval second
5. sort by recency + confidence
6. inject only a small memory bundle into the current run

## Why not persist every message

Because that would:
- pollute long-term memory with low-signal chat
- increase cross-task contamination
- make retrieval slower and noisier
- reduce trust in recall quality

## Runtime integration

Recommended runtime integration:
- `message:preprocessed` hook for selective fact/event capture
- `session:compact:after` hook for summary capture
- `agent:bootstrap` hook for recall bundle injection

This gives a full write + recall loop without transcript dumping.
