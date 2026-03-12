#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
DB_PATH = DATA_DIR / 'memory.db'


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def connect() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA journal_mode=WAL;')
    conn.execute('PRAGMA synchronous=NORMAL;')
    conn.execute('PRAGMA foreign_keys=ON;')
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(
        '''
        CREATE TABLE IF NOT EXISTS facts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            scope TEXT NOT NULL DEFAULT 'global',
            source TEXT NOT NULL DEFAULT '',
            session_key TEXT NOT NULL DEFAULT '',
            task_id TEXT NOT NULL DEFAULT '',
            confidence REAL NOT NULL DEFAULT 1.0,
            supersedes INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS task_state (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL,
            status TEXT NOT NULL,
            value TEXT NOT NULL,
            scope TEXT NOT NULL DEFAULT 'task',
            source TEXT NOT NULL DEFAULT '',
            session_key TEXT NOT NULL DEFAULT '',
            confidence REAL NOT NULL DEFAULT 1.0,
            supersedes INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS summaries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL DEFAULT '',
            value TEXT NOT NULL,
            scope TEXT NOT NULL DEFAULT 'summary',
            source TEXT NOT NULL DEFAULT '',
            session_key TEXT NOT NULL DEFAULT '',
            confidence REAL NOT NULL DEFAULT 0.7,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5(
            key, value, source, session_key, task_id, scope,
            content='facts', content_rowid='id'
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS task_state_fts USING fts5(
            task_id, status, value, source, session_key, scope,
            content='task_state', content_rowid='id'
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS summaries_fts USING fts5(
            task_id, value, source, session_key, scope,
            content='summaries', content_rowid='id'
        );

        CREATE TRIGGER IF NOT EXISTS facts_ai AFTER INSERT ON facts BEGIN
          INSERT INTO facts_fts(rowid, key, value, source, session_key, task_id, scope)
          VALUES (new.id, new.key, new.value, new.source, new.session_key, new.task_id, new.scope);
        END;
        CREATE TRIGGER IF NOT EXISTS facts_ad AFTER DELETE ON facts BEGIN
          INSERT INTO facts_fts(facts_fts, rowid, key, value, source, session_key, task_id, scope)
          VALUES('delete', old.id, old.key, old.value, old.source, old.session_key, old.task_id, old.scope);
        END;
        CREATE TRIGGER IF NOT EXISTS facts_au AFTER UPDATE ON facts BEGIN
          INSERT INTO facts_fts(facts_fts, rowid, key, value, source, session_key, task_id, scope)
          VALUES('delete', old.id, old.key, old.value, old.source, old.session_key, old.task_id, old.scope);
          INSERT INTO facts_fts(rowid, key, value, source, session_key, task_id, scope)
          VALUES (new.id, new.key, new.value, new.source, new.session_key, new.task_id, new.scope);
        END;

        CREATE TRIGGER IF NOT EXISTS task_state_ai AFTER INSERT ON task_state BEGIN
          INSERT INTO task_state_fts(rowid, task_id, status, value, source, session_key, scope)
          VALUES (new.id, new.task_id, new.status, new.value, new.source, new.session_key, new.scope);
        END;
        CREATE TRIGGER IF NOT EXISTS task_state_ad AFTER DELETE ON task_state BEGIN
          INSERT INTO task_state_fts(task_state_fts, rowid, task_id, status, value, source, session_key, scope)
          VALUES('delete', old.id, old.task_id, old.status, old.value, old.source, old.session_key, old.scope);
        END;
        CREATE TRIGGER IF NOT EXISTS task_state_au AFTER UPDATE ON task_state BEGIN
          INSERT INTO task_state_fts(task_state_fts, rowid, task_id, status, value, source, session_key, scope)
          VALUES('delete', old.id, old.task_id, old.status, old.value, old.source, old.session_key, old.scope);
          INSERT INTO task_state_fts(rowid, task_id, status, value, source, session_key, scope)
          VALUES (new.id, new.task_id, new.status, new.value, new.source, new.session_key, new.scope);
        END;

        CREATE TRIGGER IF NOT EXISTS summaries_ai AFTER INSERT ON summaries BEGIN
          INSERT INTO summaries_fts(rowid, task_id, value, source, session_key, scope)
          VALUES (new.id, new.task_id, new.value, new.source, new.session_key, new.scope);
        END;
        CREATE TRIGGER IF NOT EXISTS summaries_ad AFTER DELETE ON summaries BEGIN
          INSERT INTO summaries_fts(summaries_fts, rowid, task_id, value, source, session_key, scope)
          VALUES('delete', old.id, old.task_id, old.value, old.source, old.session_key, old.scope);
        END;
        CREATE TRIGGER IF NOT EXISTS summaries_au AFTER UPDATE ON summaries BEGIN
          INSERT INTO summaries_fts(summaries_fts, rowid, task_id, value, source, session_key, scope)
          VALUES('delete', old.id, old.task_id, old.value, old.source, old.session_key, old.scope);
          INSERT INTO summaries_fts(rowid, task_id, value, source, session_key, scope)
          VALUES (new.id, new.task_id, new.value, new.source, new.session_key, new.scope);
        END;
        '''
    )
    conn.commit()


def put_fact(args: argparse.Namespace) -> int:
    conn = connect()
    init_db(conn)
    ts = now_iso()
    conn.execute(
        '''INSERT INTO facts (key, value, scope, source, session_key, task_id, confidence, supersedes, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        (args.key, args.value, args.scope, args.source, args.session_key, args.task_id, args.confidence, args.supersedes, ts, ts),
    )
    conn.commit()
    print(json.dumps({'ok': True, 'kind': 'fact', 'key': args.key, 'value': args.value}, ensure_ascii=False))
    return 0


def put_task(args: argparse.Namespace) -> int:
    conn = connect()
    init_db(conn)
    ts = now_iso()
    conn.execute(
        '''INSERT INTO task_state (task_id, status, value, scope, source, session_key, confidence, supersedes, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        (args.task_id, args.status, args.value, args.scope, args.source, args.session_key, args.confidence, args.supersedes, ts, ts),
    )
    conn.commit()
    print(json.dumps({'ok': True, 'kind': 'task_state', 'task_id': args.task_id, 'status': args.status}, ensure_ascii=False))
    return 0


def put_summary(args: argparse.Namespace) -> int:
    conn = connect()
    init_db(conn)
    ts = now_iso()
    conn.execute(
        '''INSERT INTO summaries (task_id, value, scope, source, session_key, confidence, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
        (args.task_id, args.value, args.scope, args.source, args.session_key, args.confidence, ts, ts),
    )
    conn.commit()
    print(json.dumps({'ok': True, 'kind': 'summary', 'task_id': args.task_id}, ensure_ascii=False))
    return 0


def search(args: argparse.Namespace) -> int:
    conn = connect()
    init_db(conn)
    q = args.query
    limit = args.limit
    results = []

    fact_rows = conn.execute(
        '''SELECT 'fact' AS kind, f.id, f.key AS title, f.value, f.scope, f.source, f.session_key, f.task_id,
                  f.confidence, f.created_at, f.updated_at
           FROM facts_fts ff JOIN facts f ON f.id = ff.rowid
           WHERE facts_fts MATCH ?
           ORDER BY f.updated_at DESC
           LIMIT ?''',
        (q, limit),
    ).fetchall()
    task_rows = conn.execute(
        '''SELECT 'task_state' AS kind, t.id, t.status AS title, t.value, t.scope, t.source, t.session_key, t.task_id,
                  t.confidence, t.created_at, t.updated_at
           FROM task_state_fts tf JOIN task_state t ON t.id = tf.rowid
           WHERE task_state_fts MATCH ?
           ORDER BY t.updated_at DESC
           LIMIT ?''',
        (q, limit),
    ).fetchall()
    summary_rows = conn.execute(
        '''SELECT 'summary' AS kind, s.id, s.task_id AS title, s.value, s.scope, s.source, s.session_key, s.task_id,
                  s.confidence, s.created_at, s.updated_at
           FROM summaries_fts sf JOIN summaries s ON s.id = sf.rowid
           WHERE summaries_fts MATCH ?
           ORDER BY s.updated_at DESC
           LIMIT ?''',
        (q, limit),
    ).fetchall()

    for row in list(fact_rows) + list(task_rows) + list(summary_rows):
        results.append(dict(row))

    results.sort(key=lambda r: (r['updated_at'], r['confidence']), reverse=True)
    print(json.dumps(results[:limit], ensure_ascii=False, indent=2))
    return 0


def context(args: argparse.Namespace) -> int:
    conn = connect()
    init_db(conn)
    results = []
    if args.task_id:
        rows = conn.execute(
            '''SELECT 'task_state' AS kind, id, status AS title, value, scope, source, session_key, task_id, confidence, created_at, updated_at
               FROM task_state WHERE task_id = ?
               UNION ALL
               SELECT 'summary' AS kind, id, task_id AS title, value, scope, source, session_key, task_id, confidence, created_at, updated_at
               FROM summaries WHERE task_id = ?
               UNION ALL
               SELECT 'fact' AS kind, id, key AS title, value, scope, source, session_key, task_id, confidence, created_at, updated_at
               FROM facts WHERE task_id = ?
               ORDER BY updated_at DESC
               LIMIT ?''',
            (args.task_id, args.task_id, args.task_id, args.limit),
        ).fetchall()
        results = [dict(r) for r in rows]
    elif args.session_key:
        rows = conn.execute(
            '''SELECT 'fact' AS kind, id, key AS title, value, scope, source, session_key, task_id, confidence, created_at, updated_at
               FROM facts WHERE session_key = ?
               UNION ALL
               SELECT 'task_state' AS kind, id, status AS title, value, scope, source, session_key, task_id, confidence, created_at, updated_at
               FROM task_state WHERE session_key = ?
               UNION ALL
               SELECT 'summary' AS kind, id, task_id AS title, value, scope, source, session_key, task_id, confidence, created_at, updated_at
               FROM summaries WHERE session_key = ?
               ORDER BY updated_at DESC
               LIMIT ?''',
            (args.session_key, args.session_key, args.session_key, args.limit),
        ).fetchall()
        results = [dict(r) for r in rows]
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog='memory_core')
    sub = parser.add_subparsers(dest='cmd', required=True)

    pf = sub.add_parser('put-fact')
    pf.add_argument('--key', required=True)
    pf.add_argument('--value', required=True)
    pf.add_argument('--scope', default='global')
    pf.add_argument('--source', default='')
    pf.add_argument('--session-key', default='')
    pf.add_argument('--task-id', default='')
    pf.add_argument('--confidence', type=float, default=1.0)
    pf.add_argument('--supersedes', type=int)
    pf.set_defaults(handler=put_fact)

    pt = sub.add_parser('put-task')
    pt.add_argument('--task-id', required=True)
    pt.add_argument('--status', required=True)
    pt.add_argument('--value', required=True)
    pt.add_argument('--scope', default='task')
    pt.add_argument('--source', default='')
    pt.add_argument('--session-key', default='')
    pt.add_argument('--confidence', type=float, default=1.0)
    pt.add_argument('--supersedes', type=int)
    pt.set_defaults(handler=put_task)

    ps = sub.add_parser('put-summary')
    ps.add_argument('--task-id', default='')
    ps.add_argument('--value', required=True)
    ps.add_argument('--scope', default='summary')
    ps.add_argument('--source', default='')
    ps.add_argument('--session-key', default='')
    ps.add_argument('--confidence', type=float, default=0.7)
    ps.set_defaults(handler=put_summary)

    se = sub.add_parser('search')
    se.add_argument('--query', required=True)
    se.add_argument('--limit', type=int, default=10)
    se.set_defaults(handler=search)

    cx = sub.add_parser('context')
    cx.add_argument('--task-id', default='')
    cx.add_argument('--session-key', default='')
    cx.add_argument('--limit', type=int, default=20)
    cx.set_defaults(handler=context)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.handler(args))


if __name__ == '__main__':
    sys.exit(main())
