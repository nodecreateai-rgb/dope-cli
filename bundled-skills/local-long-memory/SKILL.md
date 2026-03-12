# local-long-memory

本地长期记忆全局 skill。

## 目标

为 OpenClaw 提供一个**完全本地、无 API、快速、小巧、准确**的长期记忆系统。

它不是“把所有聊天都塞进上下文”，而是：

- 用本地 SQLite 保存长期记忆
- 通过 FTS5 做按需检索
- 严格区分：`facts` / `task_state` / `summaries`
- 每次会话只查询当前需要的记忆
- 减少多任务、多会话、并发场景下的串味与幻觉

## 适用场景

- 需要跨会话保留长期记忆
- 需要多任务并发时保持状态准确
- 需要为 OpenClaw / dope CLI 提供可解释、可查询的本地 memory core

## 设计原则

1. **本地优先**：不依赖外部 API
2. **快**：SQLite + FTS5
3. **小**：先做文本/结构化记忆，不引入重型依赖
4. **准**：事实、任务状态、摘要分层
5. **按需查询**：不要每轮全量加载
6. **可追溯**：每条记录都带 source / session / task / timestamp

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

### 3. 写入摘要
```bash
python3 scripts/memory_core.py put-summary \
  --task-id dope-release \
  --value "linux side is validated; windows still needs real smoke" \
  --source main
```

### 4. 搜索
```bash
python3 scripts/memory_core.py search --query "dope tenant renew" --limit 5
```

### 5. 按 task 取上下文
```bash
python3 scripts/memory_core.py context --task-id dope-release --limit 20
```

## 数据模型

### facts
- 稳定、可验证事实
- 支持 key + supersede 语义

### task_state
- 任务相关状态
- 用于多任务/并发任务隔离

### summaries
- 仅做压缩视图
- 不作为唯一真相源

## 边界

当前 MVP：
- 还没有本地 embedding
- 还没有 entity graph
- 还没有自动冲突归并
- 但已经具备一个**可运行、可扩展、快且可解释**的长记忆核心

## 后续建议

下一阶段可加：
- local embeddings
- conflict check
- stale fact pruning
- OpenClaw 会话前自动按 task/session 查询
- dope CLI 子命令集成
