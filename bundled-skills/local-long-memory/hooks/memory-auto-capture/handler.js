import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

const HOOK_KEY = 'memory-auto-capture';
const DEFAULTS = {
  enabled: true,
  dmOnly: true,
  maxTextLength: 1200,
  allowSummaryOnCompact: true,
};

function getCfg(cfg) {
  const entries = cfg?.hooks?.internal?.entries;
  return { ...DEFAULTS, ...(entries?.[HOOK_KEY] || {}) };
}

function isDirectMessageContext(event) {
  const key = String(event?.sessionKey || '').toLowerCase();
  return key.includes(':user:') || key.includes(':dm:') || key.includes(':direct:') || key.startsWith('agent:main:feishu:user:');
}

function runMemory(args, cwd = '/root/.openclaw') {
  return spawnSync('python3', ['/root/.openclaw/skills/local-long-memory/scripts/memory_core.py', ...args], {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function sanitize(text, maxLen) {
  return String(text || '').replace(/\s+/g, ' ').trim().slice(0, maxLen);
}

function maybeCaptureFact(text) {
  const raw = String(text || '').trim();
  const patterns = [
    /^(?:记住|记一下|请记住)[:：]?\s*(.+)$/u,
    /^(?:以后默认|默认)[:：]?\s*(.+)$/u,
    /^(?:偏好|我偏好|我的偏好)[:：]?\s*(.+)$/u,
    /^(?:约定|规则)[:：]?\s*(.+)$/u,
  ];
  for (const re of patterns) {
    const m = raw.match(re);
    if (m) return m[1].trim();
  }
  return '';
}

function maybeCaptureEvent(text) {
  const raw = String(text || '').trim();
  const pass = raw.match(/^(?:验证通过|测试通过|成功了|已验证|验证成功)[:：]?\s*(.+)$/u);
  if (pass) return { type: 'verified_result', value: pass[1].trim() };
  const fail = raw.match(/^(?:失败了|测试失败|验证失败)[:：]?\s*(.+)$/u);
  if (fail) return { type: 'failure_result', value: fail[1].trim() };
  return null;
}

function deriveTaskId(text) {
  const raw = String(text || '').toLowerCase();
  const known = [
    ['dope', 'dope-cli'],
    ['tenant', 'tenant-mode'],
    ['memory', 'local-long-memory'],
    ['windows', 'windows-tenant-parity'],
    ['browser', 'browser-docker-use'],
  ];
  for (const [token, taskId] of known) {
    if (raw.includes(token)) return taskId;
  }
  return '';
}

function handleMessagePreprocessed(event) {
  if (event.type !== 'message' || event.action !== 'preprocessed') return;
  const cfg = getCfg(event.context?.cfg);
  if (cfg.enabled === false) return;
  if (cfg.dmOnly && !isDirectMessageContext(event)) return;

  const text = sanitize(event.context?.bodyForAgent || event.context?.content || event.context?.body || '', cfg.maxTextLength);
  if (!text) return;

  const sessionKey = String(event.sessionKey || '');
  const taskId = deriveTaskId(text);

  const factValue = maybeCaptureFact(text);
  if (factValue) {
    const key = `chat.fact.${Date.now()}`;
    runMemory(['put-fact', '--key', key, '--value', factValue, '--source', 'message:preprocessed', '--session-key', sessionKey, '--task-id', taskId]);
  }

  const eventCapture = maybeCaptureEvent(text);
  if (eventCapture) {
    runMemory(['put-event', '--event-type', eventCapture.type, '--value', eventCapture.value, '--source', 'message:preprocessed', '--session-key', sessionKey, '--task-id', taskId]);
  }
}

function handleSessionCompactAfter(event) {
  if (event.type !== 'session' || event.action !== 'compact:after') return;
  const cfg = getCfg(event.context?.cfg);
  if (cfg.enabled === false || !cfg.allowSummaryOnCompact) return;
  if (cfg.dmOnly && !isDirectMessageContext(event)) return;

  const sessionKey = String(event.sessionKey || '');
  const taskId = String(event.context?.taskId || '');
  if (!sessionKey) return;

  const summaryText = sanitize(event.context?.summary || event.context?.compactionSummary || 'session compacted', cfg.maxTextLength);
  runMemory(['put-summary', '--task-id', taskId, '--value', summaryText, '--source', 'session:compact:after', '--session-key', sessionKey, '--confidence', '0.6']);
}

export default async function memoryAutoCaptureHook(event) {
  try {
    handleMessagePreprocessed(event);
    handleSessionCompactAfter(event);
  } catch {
    // stay quiet; hooks should not break message flow
  }
}
