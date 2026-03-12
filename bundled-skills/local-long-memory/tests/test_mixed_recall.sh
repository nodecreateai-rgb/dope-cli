#!/usr/bin/env bash
set -euo pipefail
cd /root/.paco

rsync -a --delete /root/.paco/skills/local-long-memory/ /root/.openclaw/skills/local-long-memory/
rm -rf /root/.openclaw/hooks/memory-preload-bundle /root/.openclaw/hooks/memory-auto-capture
cp -a /root/.paco/skills/local-long-memory/hooks/memory-preload-bundle /root/.openclaw/hooks/
cp -a /root/.paco/skills/local-long-memory/hooks/memory-auto-capture /root/.openclaw/hooks/

python3 - <<'PY'
import sqlite3
conn=sqlite3.connect('/root/.openclaw/skills/local-long-memory/data/memory.db')
for sql in [
    "DELETE FROM facts WHERE task_id IN ('mix-task-alpha','mix-task-beta','mix-task-gamma') OR session_key IN ('agent:main:feishu:user:mix-alpha','agent:main:feishu:user:mix-beta','agent:main:feishu:user:mix-gamma') OR value IN ('global default stable','task alpha default precise','task alpha rule scoped','task beta choose simpler flow','session alpha hotfix default','session beta keep conservative')",
    "DELETE FROM events WHERE task_id IN ('mix-task-alpha','mix-task-beta','mix-task-gamma') OR session_key IN ('agent:main:feishu:user:mix-alpha','agent:main:feishu:user:mix-beta','agent:main:feishu:user:mix-gamma') OR value IN ('task alpha verification ok','task beta verification failed')",
    "DELETE FROM summaries WHERE task_id IN ('mix-task-alpha','mix-task-beta','mix-task-gamma') OR session_key IN ('agent:main:feishu:user:mix-alpha','agent:main:feishu:user:mix-beta','agent:main:feishu:user:mix-gamma')",
    "DELETE FROM task_state WHERE task_id IN ('mix-task-alpha','mix-task-beta','mix-task-gamma') OR session_key IN ('agent:main:feishu:user:mix-alpha','agent:main:feishu:user:mix-beta','agent:main:feishu:user:mix-gamma')",
]:
    conn.execute(sql)
conn.commit()
print('cleaned mixed recall rows')
PY

python3 /root/.openclaw/skills/local-long-memory/scripts/memory_core.py put-fact --key preference.default --value 'global default stable' --source test >/dev/null
python3 /root/.openclaw/skills/local-long-memory/scripts/memory_core.py put-fact --key preference.default --value 'task alpha default precise' --task-id mix-task-alpha --source test >/dev/null
python3 /root/.openclaw/skills/local-long-memory/scripts/memory_core.py put-fact --key rule.explicit --value 'task alpha rule scoped' --task-id mix-task-alpha --source test >/dev/null
python3 /root/.openclaw/skills/local-long-memory/scripts/memory_core.py put-fact --key decision.explicit --value 'task beta choose simpler flow' --task-id mix-task-beta --source test >/dev/null
python3 /root/.openclaw/skills/local-long-memory/scripts/memory_core.py put-event --task-id mix-task-alpha --event-type verification.pass --value 'task alpha verification ok' --source test >/dev/null
python3 /root/.openclaw/skills/local-long-memory/scripts/memory_core.py put-event --task-id mix-task-beta --event-type verification.fail --value 'task beta verification failed' --source test >/dev/null
python3 /root/.openclaw/skills/local-long-memory/scripts/memory_core.py put-fact --key preference.default --value 'session alpha hotfix default' --task-id mix-task-alpha --session-key agent:main:feishu:user:mix-alpha --source test >/dev/null
python3 /root/.openclaw/skills/local-long-memory/scripts/memory_core.py put-fact --key preference.default --value 'session beta keep conservative' --task-id mix-task-beta --session-key agent:main:feishu:user:mix-beta --source test >/dev/null

cat >/tmp/test-mixed-recall.mjs <<'EOF'
import hookRecall from '/root/.openclaw/hooks/memory-preload-bundle/handler.js';
import fs from 'node:fs';
const cfg = JSON.parse(fs.readFileSync('/root/.openclaw/openclaw.json', 'utf8'));
const sessionDir = '/root/.openclaw/agents/main/sessions';
fs.mkdirSync(sessionDir, { recursive: true });
const cases = [
  {
    sessionKey: 'agent:main:feishu:user:mix-alpha',
    sessionId: 'mix-alpha-session',
    ask: '当前默认规则是什么，task alpha 现在怎么做',
    out: '/tmp/mix-alpha.out'
  },
  {
    sessionKey: 'agent:main:feishu:user:mix-beta',
    sessionId: 'mix-beta-session',
    ask: '最近验证结果怎么样，task beta 失败了吗',
    out: '/tmp/mix-beta.out'
  },
  {
    sessionKey: 'agent:main:feishu:user:mix-gamma',
    sessionId: 'mix-gamma-session',
    ask: '默认规则是什么',
    out: '/tmp/mix-gamma.out'
  }
];
for (const item of cases) {
  const line = JSON.stringify({ type:'message', message:{ role:'user', content:[{ type:'text', text:item.ask }] } });
  fs.writeFileSync(sessionDir + '/' + item.sessionId + '.jsonl', line + '\n', 'utf8');
  const event = { type:'agent', action:'bootstrap', sessionKey:item.sessionKey, timestamp:new Date(), messages:[], context:{ workspaceDir:'/root/.openclaw', agentId:'main', sessionId:item.sessionId, cfg, bootstrapFiles:[{ name:'MEMORY.md', path:'/root/.openclaw/MEMORY.md', content:'# MEMORY.md\n\n## Long-term Memory\n', missing:false }] } };
  await hookRecall(event);
  fs.writeFileSync(item.out, event.context.bootstrapFiles[0].content, 'utf8');
}
EOF
node /tmp/test-mixed-recall.mjs

python3 - <<'PY'
from pathlib import Path
alpha = Path('/tmp/mix-alpha.out').read_text()
beta = Path('/tmp/mix-beta.out').read_text()
gamma = Path('/tmp/mix-gamma.out').read_text()
assert 'session alpha hotfix default' in alpha
assert 'task alpha rule scoped' in alpha
assert 'session beta keep conservative' not in alpha
assert 'task beta choose simpler flow' not in alpha
assert 'task beta verification failed' in beta
assert 'session beta keep conservative' in beta or 'task beta choose simpler flow' in beta
assert 'session alpha hotfix default' not in beta
assert 'task alpha rule scoped' not in beta
assert 'global default stable' in gamma
assert 'session alpha hotfix default' not in gamma
assert 'session beta keep conservative' not in gamma
print('mixed_recall_regression=PASS')
print('alpha_len=', len(alpha))
print('beta_len=', len(beta))
print('gamma_len=', len(gamma))
PY
