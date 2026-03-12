# local-long-memory

本地长期记忆全局 skill。

## 目标

为 OpenClaw 提供一个**完全本地、无 API、快速、小巧、准确**的长期记忆系统。

它不是“把所有聊天都塞进上下文”，而是：

- 用本地 SQLite 保存长期记忆
- 通过 FTS5 做按需检索
- 严格区分：`facts` / `task_state` / `events` / `summaries`
- 每次会话只查询当前需要的记忆
- 减少多任务、多会话、并发场景下的串味与幻觉

## 适用场景

- 需要跨会话保留长期记忆
- 需要多任务并发时保持状态准确
- 需要为 OpenClaw / 安装后的运行时提供可解释、可查询的本地 memory core

## 设计原则

1. **本地优先**：不依赖外部 API
2. **快**：SQLite + FTS5 + task/session scoped 查询
3. **小**：先做文本/结构化记忆，不引入重型依赖
4. **准**：事实、任务状态、事件、摘要分层
5. **按需查询**：不要每轮全量加载
6. **可追溯**：每条记录都带 source / session / task / timestamp

## 写入时机（关键规则）

### 不是每条消息都立刻写长期记忆
如果每条消息都直接入库，会导致：
- 噪音膨胀
- 闲聊污染
- 多任务串味
- 查询变慢

### 正确策略：分层写入

#### A. 实时写入（message:preprocessed）
只写**高信号、高确定性**内容，例如：
- 用户明确说“记住/以后默认/偏好/规则”
- 已验证通过/失败的结论
- 明确可复用的规则或约定

写入目标：
- `facts`
- `events`

#### B. 阶段收敛（session:compact:after）
在会话压缩/阶段结束后，把阶段理解沉淀为：
- `summaries`

这样做的好处：
- 不把原始聊天流水账直接塞进长期记忆
- 保持数据库小而准
- 让 recall 更稳定

## 会话前按需查询接入

`local-long-memory` 不应停留在“有脚本可手动调用”。
正确接法是：

- 在 OpenClaw 的 `agent:bootstrap` 阶段运行一个 preload hook
- 从当前 session 的最近用户消息提取 query basis
- 优先按 `session_key` / `task_id` scoped recall
- 再做小范围 FTS 搜索
- 生成一个短小的 `Dynamic Memory Bundle`
- 注入到当前轮的 `MEMORY.md` 上下文中

对应 hook：
- `hooks/memory-preload-bundle/HOOK.md`
- `hooks/memory-preload-bundle/handler.js`

## 自动写入接入

对应 hook：
- `hooks/memory-auto-capture/HOOK.md`
- `hooks/memory-auto-capture/handler.js`

职责：
- 在 `message:preprocessed` 事件中抓高信号 facts/events
- 在 `session:compact:after` 事件中写 summary

## 当前 MVP 能力

使用脚本：`scripts/memory_core.py`

### 1. 写入事实
```bash
python3 scripts/memory_core.py put-fact \
  --key repo.dope.url \
  --value https://github.com/nodecreateai-rgb/dope-cli \
  --source main \
  --scope global
```

### 2. 写入任务状态
```bash
python3 scripts/memory_core.py put-task \
  --task-id dope-release \
  --status completed \
  --value "dope cli linux real proxy tenant create passed" \
  --source main
```

### 3. 写入事件
```bash
python3 scripts/memory_core.py put-event \
  --task-id dope-release \
  --event-type test_passed \
  --value "multi tenant isolation passed" \
  --source main \
  --session-key main-session
```

### 4. 搜索
```bash
python3 scripts/memory_core.py search --query "tenant renew" --task-id dope-release --limit 5
```

### 5. 按 task 取上下文
```bash
python3 scripts/memory_core.py context --task-id dope-release --limit 20
```

### 6. 任务收敛成长期摘要
```bash
python3 scripts/memory_core.py finalize-task --task-id dope-release --source main
```
