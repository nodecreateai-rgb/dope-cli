#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf data

python3 scripts/memory_core.py put-fact --key repo.dope.url --value https://github.com/nodecreateai-rgb/dope-cli --source test --task-id dope-release >/dev/null
python3 scripts/memory_core.py put-task --task-id dope-release --status completed --value "linux proxy tenant create passed" --source test >/dev/null
python3 scripts/memory_core.py put-event --task-id dope-release --event-type test_passed --value "multi tenant isolation passed" --source test --session-key s1 >/dev/null
python3 scripts/memory_core.py put-event --task-id dope-release --event-type verification.pass --value "task scoped verification ok" --source test >/dev/null
python3 scripts/memory_core.py put-summary --task-id dope-release --value "windows still needs real smoke" --source test >/dev/null
python3 scripts/memory_core.py search --query dope --limit 5 > /tmp/local-memory-search.json
python3 scripts/memory_core.py search --query passed --task-id dope-release --limit 10 > /tmp/local-memory-search-scoped.json
python3 scripts/memory_core.py context --task-id dope-release --limit 10 > /tmp/local-memory-context.json
python3 scripts/memory_core.py finalize-task --task-id dope-release --source test --session-key s1 >/tmp/local-memory-finalize.json

python3 scripts/memory_core.py put-fact --key preference.default --value global-v1 --source test >/dev/null
python3 scripts/memory_core.py put-fact --key preference.default --value task-alpha-v1 --task-id task-alpha --source test >/dev/null
python3 scripts/memory_core.py put-fact --key preference.default --value session-alpha-v1 --task-id task-alpha --session-key session-alpha --source test >/dev/null
python3 scripts/memory_core.py get-current-fact --key preference.default --scope-mode exact > /tmp/local-memory-global.json
python3 scripts/memory_core.py get-current-fact --key preference.default --task-id task-alpha --scope-mode exact > /tmp/local-memory-task.json
python3 scripts/memory_core.py get-current-fact --key preference.default --task-id task-alpha --session-key session-alpha --scope-mode exact > /tmp/local-memory-session.json
python3 scripts/memory_core.py get-current-fact --key preference.default --task-id task-beta --scope-mode fallback > /tmp/local-memory-fallback.json
python3 scripts/memory_core.py put-fact --key preference.default --value session-alpha-v2 --task-id task-alpha --session-key session-alpha --source test --supersedes 7 >/dev/null
python3 scripts/memory_core.py get-current-fact --key preference.default --task-id task-alpha --scope-mode exact > /tmp/local-memory-task-after.json
python3 scripts/memory_core.py get-current-fact --key preference.default --task-id task-alpha --session-key session-alpha --scope-mode exact > /tmp/local-memory-session-after.json
python3 scripts/memory_core.py search --query alpha --task-id task-alpha --limit 20 > /tmp/local-memory-task-search-clean.json
python3 scripts/memory_core.py context --task-id task-alpha --limit 20 > /tmp/local-memory-task-context-clean.json

python3 - <<'PY'
import json
s=json.load(open('/tmp/local-memory-search.json'))
ss=json.load(open('/tmp/local-memory-search-scoped.json'))
c=json.load(open('/tmp/local-memory-context.json'))
f=json.load(open('/tmp/local-memory-finalize.json'))
g=json.load(open('/tmp/local-memory-global.json'))
t=json.load(open('/tmp/local-memory-task.json'))
se=json.load(open('/tmp/local-memory-session.json'))
fb=json.load(open('/tmp/local-memory-fallback.json'))
ta=json.load(open('/tmp/local-memory-task-after.json'))
sea=json.load(open('/tmp/local-memory-session-after.json'))
ts=json.load(open('/tmp/local-memory-task-search-clean.json'))
tc=json.load(open('/tmp/local-memory-task-context-clean.json'))
assert any('dope' in (row.get('value','') + row.get('title','')) for row in s)
assert any(row.get('task_id') == 'dope-release' for row in ss)
assert any(row.get('kind') == 'event' for row in c)
assert all((row.get('session_key') or '') == '' for row in c)
assert f['task_id'] == 'dope-release'
assert 'passed' in f['value'] or 'verification.pass' in f['value']
assert g['value'] == 'global-v1'
assert t['value'] == 'task-alpha-v1'
assert se['value'] == 'session-alpha-v1'
assert fb['value'] == 'global-v1'
assert ta['value'] == 'task-alpha-v1'
assert sea['value'] == 'session-alpha-v2'
assert all((row.get('session_key') or '') == '' for row in ts)
assert all((row.get('session_key') or '') == '' for row in tc)
print('local-long-memory-test=PASS')
PY
