#!/usr/bin/env bash
set -euo pipefail

cd /root/.paco/dope-cli

python3 -m py_compile ./dope
python3 ./dope tenant info --help | grep -q -- '--json'
python3 ./dope tenant info t301 --json >/tmp/dope-tenant-info-t301-json-after-fix.json
python3 - <<'PY'
import json
from pathlib import Path
obj=json.loads(Path('/tmp/dope-tenant-info-t301-json-after-fix.json').read_text())
assert obj['shortUuid'] == 't301'
assert obj['tenant'] == 'tenant-20260313021513-t301'
assert obj['baseUrl'].startswith('http://host.docker.internal:')
assert obj['model'] == 'gpt-5.4'
assert 'apiKey' not in obj
assert 'host_api_key' not in obj
assert 'feishu_app_secret' not in obj
print('tenant_info_json_flag=PASS')
PY

python3 - <<'PY'
import json
import hashlib
import subprocess
from pathlib import Path

cfg_path = Path('/root/.openclaw/config.json')
if not cfg_path.exists():
    cfg_path = Path('/root/.openclaw/openclaw.json')
runtime_cfg = json.loads(cfg_path.read_text())
hooks = runtime_cfg.get('hooks', {}).get('internal', {}).get('entries', {})
skills = runtime_cfg.get('skills', {}).get('entries', {})
assert hooks.get('memory-preload-bundle', {}).get('enabled') is True
assert hooks.get('memory-auto-capture', {}).get('enabled') is True
assert skills.get('local-long-memory', {}).get('enabled') is True
print('runtime_memory_enabled=PASS')

pairs = [
    (
        '/root/.paco/dope-cli/bundled-skills/local-long-memory/scripts/memory_core.py',
        '/root/.openclaw/skills/local-long-memory/scripts/memory_core.py',
    ),
    (
        '/root/.paco/dope-cli/bundled-skills/local-long-memory/hooks/memory-preload-bundle/handler.js',
        '/root/.openclaw/hooks/memory-preload-bundle/handler.js',
    ),
    (
        '/root/.paco/dope-cli/bundled-skills/local-long-memory/hooks/memory-auto-capture/handler.js',
        '/root/.openclaw/hooks/memory-auto-capture/handler.js',
    ),
]
for a, b in pairs:
    ha = hashlib.sha256(Path(a).read_bytes()).hexdigest()
    hb = hashlib.sha256(Path(b).read_bytes()).hexdigest()
    assert ha == hb, (a, b, ha, hb)
print('runtime_memory_latest=PASS')

subprocess.run(['bash', '/root/.paco/dope-cli/bundled-skills/local-long-memory/tests/test_mixed_recall.sh'], check=True)
subprocess.run(['bash', '/root/.paco/dope-cli/bundled-skills/local-long-memory/tests/test_memory_pressure.sh'], check=True)
print('runtime_memory_functional=PASS')
PY
