#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf data
python3 scripts/memory_core.py put-fact --key repo.dope.url --value https://github.com/nodecreateai-rgb/dope-cli --source test --task-id dope-release >/dev/null
python3 scripts/memory_core.py put-task --task-id dope-release --status completed --value "linux proxy tenant create passed" --source test >/dev/null
python3 scripts/memory_core.py put-summary --task-id dope-release --value "windows still needs real smoke" --source test >/dev/null
python3 scripts/memory_core.py search --query dope --limit 5 > /tmp/local-memory-search.json
python3 scripts/memory_core.py context --task-id dope-release --limit 10 > /tmp/local-memory-context.json
python3 - <<'PY'
import json
s=json.load(open('/tmp/local-memory-search.json'))
c=json.load(open('/tmp/local-memory-context.json'))
assert any('dope' in (row.get('value','') + row.get('title','')) for row in s)
assert any(row.get('task_id') == 'dope-release' for row in c)
print('local-long-memory-test=PASS')
PY
