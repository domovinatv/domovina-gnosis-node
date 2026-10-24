#!/usr/bin/env node
// Domovina Gnosis payment listener.
//
// Watches the local node for incoming payments to a set of wallet addresses and
// sends each one, HMAC-signed, to a webhook (the Cloudflare Worker that does
// the push notifications). See docs/08-wallet-notifications.md.
//
// Design:
//   - Blocks are processed strictly in order, CONFIRMATIONS behind the head.
//     The WebSocket newHeads subscription is only a wake-up signal; a poll
//     timer does the same job if the socket is down, so nothing is missed.
//   - Progress is saved in STATE_FILE after every block. On restart the
//     listener backfills from where it stopped (up to MAX_BACKFILL blocks).
//   - A block counts as processed only after its webhooks succeeded, so
//     delivery is at-least-once. Every event carries a stable `id` the
//     Worker uses to drop duplicates.
//   - Detects native xDAI transfers (tx.to + value) and ERC-20 Transfer logs.
//     Not detected: xDAI sent by a contract (internal call). That needs
//     trace_* calls; see the doc.
//
// No npm dependencies: Node 22+ has fetch and WebSocket built in.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const env = process.env;
const RPC_HTTP_URL = env.RPC_HTTP_URL || 'http://127.0.0.1:8545';
const RPC_WS_URL = env.RPC_WS_URL ?? 'ws://127.0.0.1:8546'; // empty string = poll only
const WEBHOOK_URL = env.WEBHOOK_URL || '';
const WEBHOOK_SECRET = env.WEBHOOK_SECRET || '';
const CONFIRMATIONS = Number(env.CONFIRMATIONS ?? 2);
const POLL_MS = Number(env.POLL_MS ?? 5000);
const MAX_BACKFILL = Number(env.MAX_BACKFILL ?? 720); // 720 blocks ≈ 1 h at 5 s
const STATE_FILE = env.STATE_FILE || path.resolve('listener-state.json');
const WATCHLIST_FILE = env.WATCHLIST_FILE || path.resolve('watchlist.json');
const LOG_FILE = env.LOG_FILE || ''; // empty = stdout/stderr
const PID_FILE = env.PID_FILE || '';

const TRANSFER_TOPIC = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';
const HASH_HISTORY = 64; // recent block hashes kept for reorg detection

// Monerium EURe v1 (0xcB444e90D8198415266c6a2724b7900fb12FC56E) on Gnosis is a
// legacy bridge/proxy contract that forwards every transfer to canonical EURe v2
// (0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430), causing BOTH contracts to emit
// an identical Transfer(from, to, value) log in the same transaction. Ignore the
// v1 duplicate so a single EURe payment never triggers two notifications.
const IGNORED_TOKENS = new Set(['0xcb444e90d8198415266c6a2724b7900fb12fc56e']);

// Optional comma-separated ERC-20 contract allowlist (empty = all tokens).
const TOKEN_ALLOWLIST = new Set(
  (env.TOKEN_ALLOWLIST || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
);

// With LOG_FILE set the listener owns its log file and reopens it on SIGHUP,
// which is what newsyslog sends after rotating it (config in 10-host-setup.sh).
let logStream = null;
function openLog() {
  if (!LOG_FILE) return;
  logStream?.end();
  logStream = fs.createWriteStream(LOG_FILE, { flags: 'a' });
}
function write(line) {
  if (logStream) logStream.write(line + '\n');
  else console.log(line);
}
const log = (...a) => write([new Date().toISOString(), ...a].join(' '));
const warn = (...a) => write([new Date().toISOString(), 'WARN', ...a].join(' '));
openLog();
if (PID_FILE) fs.writeFileSync(PID_FILE, String(process.pid));
process.on('SIGHUP', openLog);

if (WEBHOOK_URL && WEBHOOK_SECRET.length < 32) {
  warn('WEBHOOK_URL is set but WEBHOOK_SECRET is missing or shorter than 32 chars. Refusing to start.');
  // Exit 0: a config error must not make launchd restart us in a loop.
  logStream ? logStream.end(() => process.exit(0)) : process.exit(0);
  await new Promise(() => {});
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hex = (n) => '0x' + n.toString(16);

// ---------- JSON-RPC ----------

let rpcId = 0;
async function rpc(method, params = []) {
  const res = await fetch(RPC_HTTP_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method, params }),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) throw new Error(`${method}: HTTP ${res.status}`);
  const body = await res.json();
  if (body.error) throw new Error(`${method}: ${body.error.message}`);
  return body.result;
}

// ---------- state ----------

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch {
    return { lastBlock: null, hashes: {} };
  }
}

function saveState(state) {
  const tmp = STATE_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(state));
  fs.renameSync(tmp, STATE_FILE);
}

// ---------- watchlist (reloaded when the file changes) ----------

let watch = new Set();
let watchMtime = 0;

function refreshWatchlist() {
  let st;
  try {
    st = fs.statSync(WATCHLIST_FILE);
  } catch {
    if (watchMtime !== -1) warn(`watchlist ${WATCHLIST_FILE} not found; watching nothing`);
    watch = new Set();
    watchMtime = -1;
    return;
  }
  if (st.mtimeMs === watchMtime) return;
  const list = JSON.parse(fs.readFileSync(WATCHLIST_FILE, 'utf8'));
  watch = new Set(list.map((a) => a.toLowerCase()));
  watchMtime = st.mtimeMs;
  log(`watchlist loaded: ${watch.size} addresses`);
}

// ---------- token metadata (eth_call, cached) ----------

const tokenCache = new Map();

function decodeString(data) {
  if (!data || data === '0x') return null;
  const b = Buffer.from(data.slice(2), 'hex');
  if (b.length === 32) return b.toString('utf8').replace(/\0+$/, '') || null; // bytes32 symbols (old tokens)
  if (b.length < 64) return null;
  const len = Number(BigInt('0x' + b.subarray(32, 64).toString('hex')));
  return b.subarray(64, 64 + len).toString('utf8') || null;
}

async function tokenInfo(address) {
  if (tokenCache.has(address)) return tokenCache.get(address);
  let symbol = null;
  let decimals = null;
  try {
    symbol = decodeString(await rpc('eth_call', [{ to: address, data: '0x95d89b41' }, 'latest']));
  } catch {}
  try {
    const d = await rpc('eth_call', [{ to: address, data: '0x313ce567' }, 'latest']);
    if (d && d !== '0x') decimals = Number(BigInt(d));
  } catch {}
  const info = { symbol, decimals };
  tokenCache.set(address, info);
  return info;
}

function formatUnits(raw, decimals) {
  if (decimals == null) return null;
  const base = 10n ** BigInt(decimals);
  const whole = raw / base;
  const frac = (raw % base).toString().padStart(decimals, '0').replace(/0+$/, '');
  return frac ? `${whole}.${frac}` : whole.toString();
}

// ---------- webhook ----------

async function deliver(event) {
  if (!WEBHOOK_URL) {
    log('event (no WEBHOOK_URL, not sent):', JSON.stringify(event));
    return;
  }
  const body = JSON.stringify(event);
  for (let attempt = 1; ; attempt++) {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const signature = crypto.createHmac('sha256', WEBHOOK_SECRET).update(`${timestamp}.${body}`).digest('hex');
    try {
      const res = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-domovina-timestamp': timestamp,
          'x-domovina-signature': `sha256=${signature}`,
        },
        body,
        signal: AbortSignal.timeout(10000),
      });
      if (res.ok) {
        log(`delivered ${event.id}`);
        return;
      }
      if (res.status >= 400 && res.status < 500 && res.status !== 429) {
        // The Worker rejected the event itself; retrying will not help.
        warn(`webhook rejected ${event.id}: HTTP ${res.status}; skipping`);
        return;
      }
      warn(`webhook HTTP ${res.status} for ${event.id} (attempt ${attempt})`);
    } catch (err) {
      warn(`webhook error for ${event.id} (attempt ${attempt}): ${err.message}`);
    }
    // Keep retrying: the block is not marked processed until this succeeds.
    await sleep(Math.min(60000, 1000 * 2 ** Math.min(attempt, 6)));
  }
}

// ---------- block processing ----------

async function eventsInBlock(block) {
  const events = [];
  const base = { blockNumber: Number(BigInt(block.number)), blockHash: block.hash, timestamp: Number(BigInt(block.timestamp)) };

  for (const tx of block.transactions) {
    const to = tx.to?.toLowerCase();
    const value = BigInt(tx.value);
    if (to && value > 0n && watch.has(to)) {
      events.push({
        id: `${tx.hash}:native`,
        type: 'NATIVE_RECEIVED',
        ...base,
        txHash: tx.hash,
        from: tx.from.toLowerCase(),
        to,
        token: null,
        symbol: 'xDAI',
        decimals: 18,
        amountRaw: value.toString(),
        amount: formatUnits(value, 18),
      });
    }
  }

  // ERC-20 Transfer has 3 topics; ERC-721 Transfer has 4 and is skipped.
  const logs = await rpc('eth_getLogs', [{ blockHash: block.hash, topics: [TRANSFER_TOPIC] }]);
  for (const l of logs) {
    if (l.topics.length !== 3 || l.removed) continue;
    const to = '0x' + l.topics[2].slice(26).toLowerCase();
    if (!watch.has(to)) continue;
    const token = l.address.toLowerCase();
    if (IGNORED_TOKENS.has(token)) continue;
    if (TOKEN_ALLOWLIST.size > 0 && !TOKEN_ALLOWLIST.has(token)) continue;
    const raw = BigInt(l.data === '0x' ? 0 : l.data);
    const { symbol, decimals } = await tokenInfo(token);
    events.push({
      id: `${l.transactionHash}:${Number(BigInt(l.logIndex))}`,
      type: 'ERC20_RECEIVED',
      ...base,
      txHash: l.transactionHash,
      from: '0x' + l.topics[1].slice(26).toLowerCase(),
      to,
      token,
      symbol,
      decimals,
      amountRaw: raw.toString(),
      amount: formatUnits(raw, decimals),
    });
  }
  return events;
}

const state = loadState();
let running = false;
let again = false;

async function tick() {
  if (running) {
    again = true;
    return;
  }
  running = true;
  try {
    do {
      again = false;
      refreshWatchlist();
      const head = Number(BigInt(await rpc('eth_blockNumber')));
      const target = head - CONFIRMATIONS;
      if (state.lastBlock == null || target - state.lastBlock > MAX_BACKFILL) {
        if (state.lastBlock != null) warn(`gap of ${target - state.lastBlock} blocks exceeds MAX_BACKFILL; skipping ahead`);
        state.lastBlock = target - 1;
        state.hashes = {};
      }
      while (state.lastBlock < target) {
        const n = state.lastBlock + 1;
        const block = await rpc('eth_getBlockByNumber', [hex(n), true]);
        if (!block) break;

        const prevHash = state.hashes[n - 1];
        if (prevHash && block.parentHash !== prevHash) {
          // Reorg deeper than CONFIRMATIONS. Step back one block and re-check.
          warn(`reorg at block ${n}: parent ${block.parentHash} != stored ${prevHash}; rewinding`);
          delete state.hashes[n - 1];
          state.lastBlock = n - 2;
          continue;
        }

        for (const event of await eventsInBlock(block)) await deliver(event);

        state.lastBlock = n;
        state.hashes[n] = block.hash;
        delete state.hashes[n - HASH_HISTORY];
        saveState(state);
      }
    } while (again);
  } catch (err) {
    warn(`tick failed: ${err.message}`);
  } finally {
    running = false;
  }
}

// ---------- WebSocket wake-up ----------

function connectWs(delay = 1000) {
  if (!RPC_WS_URL) return;
  const ws = new WebSocket(RPC_WS_URL);
  ws.addEventListener('open', () => {
    log(`ws connected: ${RPC_WS_URL}`);
    delay = 1000;
    ws.send(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_subscribe', params: ['newHeads'] }));
  });
  ws.addEventListener('message', (e) => {
    const msg = JSON.parse(e.data);
    if (msg.method === 'eth_subscription') {
      const hdr = msg.params?.result;
      if (hdr?.number && hdr?.hash && state.lastBlock != null) {
        const num = Number(BigInt(hdr.number));
        // If CONFIRMATIONS=0 and a same-height tip reorg replaces block `num`,
        // rewind one block so tick() re-processes the replacement head immediately.
        if (num <= state.lastBlock && state.hashes[num] && state.hashes[num] !== hdr.hash) {
          warn(`tip reorg at block ${num}: ${hdr.hash} != stored ${state.hashes[num]}; rewinding`);
          delete state.hashes[num];
          state.lastBlock = num - 1;
        }
      }
      tick();
    }
  });
  ws.addEventListener('close', () => {
    warn(`ws closed; reconnecting in ${delay / 1000}s (polling continues)`);
    setTimeout(() => connectWs(Math.min(delay * 2, 60000)), delay);
  });
  ws.addEventListener('error', () => {}); // 'close' follows and handles reconnect
}

log(`listener start: rpc=${RPC_HTTP_URL} ws=${RPC_WS_URL || '(off)'} confirmations=${CONFIRMATIONS} webhook=${WEBHOOK_URL || '(log only)'}`);
connectWs();
setInterval(tick, POLL_MS);
tick();

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    log(`${sig}, exiting`);
    process.exit(0);
  });
}
