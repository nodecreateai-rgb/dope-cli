import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const HOOK_KEY = 'memory-preload-bundle';
const DEFAULT_DB = '/root/.openclaw/skills/local-long-memory/data/memory.db';
const DEFAULTS = {
  enabled: true,
  recentMessages: 4,
  recentScanLines: 60,
  sessionItems: 6,
  taskItems: 8,
  searchItems: 6,
  maxTaskIds: 3,
  maxChars: 4000,
  dmOnly: true,
};

function isAgentBootstrapEvent(event) {
  return event && event.type === 'agent' && event.action === 'bootstrap' && event.context;
}

function getHookConfig(cfg) {
  const entries = cfg?.hooks?.internal?.entries;
  return { ...DEFAULTS, ...(entries?.[HOOK_KEY] || {}) };
}

function isLikelyDirectSession(sessionKey) {
  const key = String(sessionKey || '').toLowerCase();
  return key.includes(':user:') || key.includes(':dm:') || key.includes(':direct:') || key.startsWith('agent:main:feishu:user:');
}

function extractText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .filter((item) => item && item.type === 'text' && typeof item.text === 'string')
    .map((item) => item.text)
    .join('\n')
    .trim();
}

function readRecentUserTexts(sessionFile, maxMessages = 4, scanLines = 60) {
  if (!sessionFile || !fs.existsSync(sessionFile)) return [];
  const lines = fs.readFileSync(sessionFile, 'utf8').split(/\r?\n/).filter(Boolean);
  const recent = [];
  for (const line of lines.slice(-scanLines).reverse()) {
    try {
      const obj = JSON.parse(line);
      if (obj?.type !== 'message') continue;
      const msg = obj.message;
      if (!msg || msg.role !== 'user') continue;
      const text = extractText(msg.content).trim();
      if (!text || text.startsWith('/')) continue;
      recent.push(text);
      if (recent.length >= maxMessages) break;
    } catch {}
  }
  return recent.reverse();
}

function tokenize(text) {
  const tokens = String(text || '')
    .toLowerCase()
    .match(/[\p{L}\p{N}][\p{L}\p{N}._:-]{1,}/gu) || [];
  const stop = new Set(['this','that','with','from','then','have','need','into','true','false','null','local','memory','skill','openclaw','继续','很好','需要','把','这个','进行','真正','接入','会话','查询','流程']);
  return [...new Set(tokens.filter((t) => t.length >= 2 && !stop.has(t)))].slice(0, 24);
}

function redact(text) {
  return String(text || '')
    .replace(/\b(sk-[A-Za-z0-9_-]{8,})\b/g, '[REDACTED_API_KEY]')
    .replace(/\b(github_pat_[A-Za-z0-9_]{8,})\b/g, '[REDACTED_GITHUB_PAT]')
    .replace(/\b(cli_[A-Za-z0-9]{8,})\b/g, '[REDACTED_APP_ID]')
    .replace(/\b([A-Za-z0-9]{24,})\b/g, (m) => (/^[A-Za-z0-9+/=]{24,}$/.test(m) ? '[REDACTED_TOKEN]' : m));
}

function openDb(dbPath) {
  if (!dbPath || !fs.existsSync(dbPath)) return null;
  return new DatabaseSync(dbPath, { open: true, readOnly: true });
}

function inferTaskIds(db, text, maxTaskIds) {
  const rows = db.prepare(`
    SELECT task_id FROM facts WHERE task_id != ''
    UNION SELECT task_id FROM task_state WHERE task_id != ''
    UNION SELECT task_id FROM summaries WHERE task_id != ''
    UNION SELECT task_id FROM events WHERE task_id != ''
  `).all();
  const hay = String(text || '').toLowerCase();
  const taskIds = rows.map((r) => String(r.task_id || '').trim()).filter(Boolean);
  const scored = [];
  for (const taskId of taskIds) {
    const lower = taskId.toLowerCase();
    let score = 0;
    if (hay.includes(lower)) score += 100;
    for (const part of lower.split(/[^a-z0-9]+/).filter(Boolean)) {
      if (part.length >= 3 && hay.includes(part)) score += 10;
    }
    if (score > 0) scored.push({ taskId, score });
  }
  scored.sort((a, b) => b.score - a.score || a.taskId.localeCompare(b.taskId));
  return scored.slice(0, maxTaskIds).map((x) => x.taskId);
}

function querySessionRows(db, sessionKey, limit) {
  if (!sessionKey) return [];
  return db.prepare(`
    SELECT * FROM (
      SELECT 'fact' AS kind, id, key AS title, value, scope, source, session_key, task_id, confidence, updated_at FROM facts WHERE session_key = ?
      UNION ALL
      SELECT 'task_state' AS kind, id, status AS title, value, scope, source, session_key, task_id, confidence, updated_at FROM task_state WHERE session_key = ?
      UNION ALL
      SELECT 'summary' AS kind, id, task_id AS title, value, scope, source, session_key, task_id, confidence, updated_at FROM summaries WHERE session_key = ?
      UNION ALL
      SELECT 'event' AS kind, id, event_type AS title, value, scope, source, session_key, task_id, confidence, updated_at FROM events WHERE session_key = ?
    ) ORDER BY updated_at DESC LIMIT ?
  `).all(sessionKey, sessionKey, sessionKey, sessionKey, limit);
}

function queryTaskRows(db, taskId, limit) {
  return db.prepare(`
    SELECT * FROM (
      SELECT 'fact' AS kind, id, key AS title, value, scope, source, session_key, task_id, confidence, updated_at FROM facts WHERE task_id = ?
      UNION ALL
      SELECT 'task_state' AS kind, id, status AS title, value, scope, source, session_key, task_id, confidence, updated_at FROM task_state WHERE task_id = ?
      UNION ALL
      SELECT 'summary' AS kind, id, task_id AS title, value, scope, source, session_key, task_id, confidence, updated_at FROM summaries WHERE task_id = ?
      UNION ALL
      SELECT 'event' AS kind, id, event_type AS title, value, scope, source, session_key, task_id, confidence, updated_at FROM events WHERE task_id = ?
    ) ORDER BY updated_at DESC LIMIT ?
  `).all(taskId, taskId, taskId, taskId, limit);
}

function querySearchRows(db, tokens, limit) {
  if (!tokens.length) return [];
  const expr = tokens.map((t) => `"${t.replace(/"/g, '""')}"`).join(' OR ');
  const rows = [];
  const queries = [
    `SELECT 'fact' AS kind, base.id, base.key AS title, base.value, base.scope, base.source, base.session_key, base.task_id, base.confidence, base.updated_at
     FROM facts_fts idx JOIN facts base ON base.id = idx.rowid
     WHERE facts_fts MATCH ? ORDER BY base.updated_at DESC LIMIT ?`,
    `SELECT 'task_state' AS kind, base.id, base.status AS title, base.value, base.scope, base.source, base.session_key, base.task_id, base.confidence, base.updated_at
     FROM task_state_fts idx JOIN task_state base ON base.id = idx.rowid
     WHERE task_state_fts MATCH ? ORDER BY base.updated_at DESC LIMIT ?`,
    `SELECT 'summary' AS kind, base.id, base.task_id AS title, base.value, base.scope, base.source, base.session_key, base.task_id, base.confidence, base.updated_at
     FROM summaries_fts idx JOIN summaries base ON base.id = idx.rowid
     WHERE summaries_fts MATCH ? ORDER BY base.updated_at DESC LIMIT ?`,
    `SELECT 'event' AS kind, base.id, base.event_type AS title, base.value, base.scope, base.source, base.session_key, base.task_id, base.confidence, base.updated_at
     FROM events_fts idx JOIN events base ON base.id = idx.rowid
     WHERE events_fts MATCH ? ORDER BY base.updated_at DESC LIMIT ?`,
  ];
  for (const sql of queries) {
    try {
      rows.push(...db.prepare(sql).all(expr, limit));
    } catch {}
  }
  rows.sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)) || Number(b.confidence || 0) - Number(a.confidence || 0));
  return rows.slice(0, limit);
}

function dedupeRows(rows) {
  const seen = new Set();
  const out = [];
  for (const row of rows) {
    const key = `${row.kind}:${row.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(row);
  }
  return out;
}

function renderRows(rows) {
  return rows.map((row) => {
    const bits = [];
    bits.push(`[${row.kind}]`);
    if (row.task_id) bits.push(`task=${row.task_id}`);
    if (row.title) bits.push(`${row.title}`);
    const head = bits.join(' ');
    const value = redact(String(row.value || '').replace(/\s+/g, ' ').trim()).slice(0, 240);
    const meta = [row.scope ? `scope=${row.scope}` : '', row.updated_at || ''].filter(Boolean).join(' · ');
    return `- ${head}: ${value}${meta ? ` (${meta})` : ''}`;
  }).join('\n');
}

function trimBlock(text, maxChars) {
  if (text.length <= maxChars) return text;
  return text.slice(0, Math.max(0, maxChars - 24)).trimEnd() + '\n\n[truncated]';
}

function injectIntoMemoryFile(context, bundleText) {
  const files = context.bootstrapFiles || [];
  const target = files.find((f) => f && f.name === 'MEMORY.md' && !f.missing);
  if (!target) return false;
  const original = typeof target.content === 'string' ? target.content : '';
  const markerStart = '\n\n## Dynamic Memory Bundle\n';
  const injected = `${original}${markerStart}${bundleText}\n`;
  target.content = injected;
  return true;
}

export default async function memoryPreloadBundleHook(event) {
  if (!isAgentBootstrapEvent(event)) return;
  const context = event.context;
  const cfg = getHookConfig(context.cfg);
  if (cfg.enabled === false) return;
  if (cfg.dmOnly && !isLikelyDirectSession(event.sessionKey)) return;
  if (!Array.isArray(context.bootstrapFiles) || !context.bootstrapFiles.some((f) => f?.name === 'MEMORY.md' && !f.missing)) return;

  const workspaceDir = context.workspaceDir || '/root/.openclaw';
  const agentId = context.agentId || 'main';
  const sessionsDir = path.join(workspaceDir, 'agents', agentId, 'sessions');
  const sessionFile = context.sessionId ? path.join(sessionsDir, `${context.sessionId}.jsonl`) : null;
  const recentTexts = readRecentUserTexts(sessionFile, cfg.recentMessages, cfg.recentScanLines);
  const queryText = recentTexts.join('\n').trim();
  if (!queryText) return;

  const db = openDb(cfg.memoryDbPath || DEFAULT_DB);
  if (!db) return;

  try {
    const tokens = tokenize(queryText);
    const taskIds = inferTaskIds(db, queryText, cfg.maxTaskIds);
    const sessionRows = dedupeRows(querySessionRows(db, event.sessionKey, cfg.sessionItems));
    const taskRows = dedupeRows(taskIds.flatMap((taskId) => queryTaskRows(db, taskId, cfg.taskItems)));
    const searchRows = dedupeRows(querySearchRows(db, tokens, cfg.searchItems));

    if (sessionRows.length === 0 && taskRows.length === 0 && searchRows.length === 0) return;

    const sections = [];
    sections.push('Generated from local-long-memory before this turn.');
    sections.push(`- recent query basis: ${redact(queryText).replace(/\s+/g, ' ').slice(0, 280)}`);
    if (taskIds.length) sections.push(`- inferred task ids: ${taskIds.join(', ')}`);

    if (sessionRows.length) {
      sections.push('\n### Session-scoped recall');
      sections.push(renderRows(sessionRows));
    }
    if (taskRows.length) {
      sections.push('\n### Task-scoped recall');
      sections.push(renderRows(taskRows));
    }
    if (searchRows.length) {
      sections.push('\n### Search hits');
      sections.push(renderRows(searchRows));
    }

    const bundle = trimBlock(sections.join('\n'), cfg.maxChars);
    injectIntoMemoryFile(context, bundle);
  } finally {
    try { db.close(); } catch {}
  }
}
