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
    "DELETE FROM facts WHERE task_id LIKE 'pressure-task-%' OR session_key LIKE 'agent:main:feishu:user:pressure-%' OR value LIKE 'pressure %'",
    "DELETE FROM events WHERE task_id LIKE 'pressure-task-%' OR session_key LIKE 'agent:main:feishu:user:pressure-%' OR value LIKE 'pressure %'",
    "DELETE FROM summaries WHERE task_id LIKE 'pressure-task-%' OR session_key LIKE 'agent:main:feishu:user:pressure-%' OR value LIKE 'pressure %'",
    "DELETE FROM task_state WHERE task_id LIKE 'pressure-task-%' OR session_key LIKE 'agent:main:feishu:user:pressure-%' OR value LIKE 'pressure %'",
]:
    conn.execute(sql)
conn.commit()
print('cleaned pressure rows')
PY

python3 - <<'PY'
import subprocess
for i in range(6):
    task = f'pressure-task-{i}'
    subprocess.run(['python3', '/root/.openclaw/skills/local-long-memory/scripts/memory_core.py', 'put-fact', '--key', 'preference.default', '--value', f'pressure global {i}', '--source', 'pressure'], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['python3', '/root/.openclaw/skills/local-long-memory/scripts/memory_core.py', 'put-fact', '--key', 'rule.explicit', '--value', f'pressure task rule {i}', '--task-id', task, '--source', 'pressure'], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['python3', '/root/.openclaw/skills/local-long-memory/scripts/memory_core.py', 'put-event', '--event-type', 'verification.pass', '--value', f'pressure verify {i}', '--task-id', task, '--source', 'pressure'], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['python3', '/root/.openclaw/skills/local-long-memory/scripts/memory_core.py', 'put-fact', '--key', 'preference.default', '--value', f'pressure session default {i}', '--task-id', task, '--session-key', f'agent:main:feishu:user:pressure-{i}', '--source', 'pressure'], check=True, stdout=subprocess.DEVNULL)
PY

cat >/tmp/test-pressure-recall.mjs <<'EOF'
import hookRecall from '/root/.openclaw/hooks/memory-preload-bundle/handler.js';
import fs from 'node:fs';
const cfg = JSON.parse(fs.readFileSync('/root/.openclaw/openclaw.json', 'utf8'));
const sessionDir = '/root/.openclaw/agents/main/sessions';
fs.mkdirSync(sessionDir, { recursive: true });
const cases = Array.from({ length: 6 }, (_, i) => ({
  sessionKey: `agent:main:feishu:user:pressure-${i}`,
  sessionId: `pressure-session-${i}`,
  ask: `当前默认规则是什么，pressure-task-${i} 现在怎么做，最近验证结果如何`,
  out: `/tmp/pressure-${i}.out`
}));
for (const item of cases) {
  const line = JSON.stringify({ type:'message', message:{ role:'user', content:[{ type:'text', text:item.ask }] } });
  fs.writeFileSync(sessionDir + '/' + item.sessionId + '.jsonl', line + '\n', 'utf8');
  const event = { type:'agent', action:'bootstrap', sessionKey:item.sessionKey, timestamp:new Date(), messages:[], context:{ workspaceDir:'/root/.openclaw', agentId:'main', sessionId:item.sessionId, cfg, bootstrapFiles:[{ name:'MEMORY.md', path:'/root/.openclaw/MEMORY.md', content:'# MEMORY.md\n\n## Long-term Memory\n', missing:false }] } };
  await hookRecall(event);
  fs.writeFileSync(item.out, event.context.bootstrapFiles[0].content, 'utf8');
}
EOF
node /tmp/test-pressure-recall.mjs

python3 - <<'PY'
from pathlib import Path
for i in range(6):
    text = Path(f'/tmp/pressure-{i}.out').read_text()
    assert f'inferred task ids: pressure-task-{i}' in text, f'wrong inferred task ids for {i}'
    assert f'pressure session default {i}' in text, f'missing session recall {i}'
    assert f'pressure task rule {i}' in text, f'missing task rule {i}'
    assert f'pressure verify {i}' in text, f'missing verification {i}'
    for j in range(6):
        if j == i:
            continue
        assert f'pressure-task-{j}' not in text.split('### Search hits')[0], f'task contamination {i}<-{j}'
        assert f'pressure session default {j}' not in text, f'session contamination {i}<-{j}'
        assert f'pressure task rule {j}' not in text, f'task contamination {i}<-{j}'
print('mixed_pressure_regression=PASS')
PY
