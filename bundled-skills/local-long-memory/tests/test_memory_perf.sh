#!/usr/bin/env bash
set -euo pipefail
cd /root/.paco

python3 - <<'PY'
import json
import shutil
import sqlite3
import subprocess
import time
from pathlib import Path

base = Path('/root/.paco/skills/local-long-memory')
data_dir = base / 'data'
if data_dir.exists():
    shutil.rmtree(data_dir)

def run(*args):
    cmd = ['python3', str(base / 'scripts' / 'memory_core.py'), *args]
    return subprocess.run(cmd, check=True, text=True, capture_output=True)

# seed a larger but still deterministic corpus
for i in range(120):
    task = f'perf-task-{i % 12}'
    session = f'perf-session-{i % 18}'
    run('put-fact', '--key', 'preference.default', '--value', f'global default {i}', '--source', 'perf')
    run('put-fact', '--key', f'fact.metric.{i}', '--value', f'task detail {i} for {task}', '--task-id', task, '--source', 'perf')
    run('put-task', '--task-id', task, '--status', 'running', '--value', f'status row {i}', '--source', 'perf')
    run('put-event', '--task-id', task, '--event-type', 'verification.pass', '--value', f'event row {i}', '--source', 'perf')
    run('put-summary', '--task-id', task, '--value', f'summary row {i}', '--source', 'perf')
    run('put-fact', '--key', 'preference.default', '--value', f'session row {i}', '--task-id', task, '--session-key', session, '--source', 'perf')

# measure query timings
queries = [
    ('search-task', ['search', '--query', 'verification', '--task-id', 'perf-task-3', '--limit', '20']),
    ('context-task', ['context', '--task-id', 'perf-task-3', '--limit', '20']),
    ('current-fact', ['get-current-fact', '--key', 'preference.default', '--task-id', 'perf-task-3', '--scope-mode', 'fallback']),
]
results = {}
for name, args in queries:
    samples = []
    for _ in range(8):
        start = time.perf_counter()
        proc = run(*args)
        elapsed_ms = (time.perf_counter() - start) * 1000
        samples.append(elapsed_ms)
        if name == 'search-task':
            rows = json.loads(proc.stdout)
            assert rows, 'search-task returned no rows'
            assert all((row.get('session_key') or '') == '' for row in rows), 'task search leaked session rows'
        elif name == 'context-task':
            rows = json.loads(proc.stdout)
            assert rows, 'context-task returned no rows'
            assert all((row.get('session_key') or '') == '' for row in rows), 'task context leaked session rows'
        elif name == 'current-fact':
            row = json.loads(proc.stdout)
            assert row.get('value'), 'current-fact returned empty result'
    results[name] = {
        'max_ms': round(max(samples), 2),
        'avg_ms': round(sum(samples) / len(samples), 2),
    }

# sanity-check db shape
conn = sqlite3.connect(data_dir / 'memory.db')
counts = {}
for table in ['facts', 'task_state', 'events', 'summaries']:
    counts[table] = conn.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
conn.close()

assert counts['facts'] >= 240, counts
assert counts['task_state'] >= 120, counts
assert counts['events'] >= 120, counts
assert counts['summaries'] >= 120, counts
assert results['search-task']['max_ms'] < 250, results
assert results['context-task']['max_ms'] < 250, results
assert results['current-fact']['max_ms'] < 250, results

print('memory_perf_regression=PASS')
print(json.dumps({'counts': counts, 'timings_ms': results}, ensure_ascii=False, indent=2))
PY
