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
8. Preference/rule/default facts support supersede chains so newer truths win without deleting history
9. Recency weighting should differ by memory class: short-lived operational state decays faster than durable preferences/rules

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

Stable keys should be used for preference/rule/default style facts so new values can supersede older ones.

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
5. rank by relevance + confidence + memory type + recency decay
6. inject only a small memory bundle into the current run

## Recency policy

- short-lived state (`events`, `task_state`, ports/runtime state): decay fast
- medium-lived summaries: moderate decay
- durable preferences/rules/defaults: slow decay

This keeps recall fast while avoiding old operational noise dominating results.
