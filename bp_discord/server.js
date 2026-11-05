'use strict';

const RES = GetCurrentResourceName();
const API = 'https://discord.com/api/v10';
const UA = 'DiscordBot (https://github.com/blueprint, 1.1) bp_discord';

const C = { reset: '^7', name: '^5[bp_discord]^7 ', ok: '^2', warn: '^3', err: '^1' };
const log = (...a) => console.log(C.name + a.join(' '));
const warn = (...a) => console.log(C.name + C.warn + a.join(' ') + C.reset);
const error = (...a) => console.log(C.name + C.err + a.join(' ') + C.reset);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function loadConfig() {
  try {
    const src = LoadResourceFile(RES, 'config.js');
    return new Function(src + '\n;return BPConfig;')() || {};
  } catch (e) {
    error('config.js could not be read:', e.message);
    return {};
  }
}
const CFG = loadConfig();
const MODE = String(GetConvar('bp_discord_mode', CFG.mode || 'builtin')).toLowerCase() === 'custom' ? 'custom' : 'builtin';
const TOKEN = GetConvar('bp_discord_token', '').trim();
const SECRET = GetConvar('bp_discord_secret', '').trim();
const ACTIVITY = GetConvar('bp_discord_activity', CFG.activity || 'over the city');
const CUSTOM_URL = GetConvar('bp_discord_url', (CFG.custom && CFG.custom.url) || 'ws://127.0.0.1:30125');

let WSCtor = globalThis.WebSocket;
if (!WSCtor) { try { WSCtor = require('ws'); } catch (_) { WSCtor = null; } }

let ready = false;
let stopped = false;
let appId = null;
const modals = {};
const claims = new Set();

function clean(payload) {
  if (!payload || typeof payload !== 'object') return payload;
  const out = Array.isArray(payload) ? [] : {};
  for (const [k, v] of Object.entries(payload)) {
    if (v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0 &&
        ['components', 'embeds', 'attachments', 'parse', 'roles', 'users'].includes(k)) {
      out[k] = [];
    } else if (v && typeof v === 'object') {
      const keys = Object.keys(v);
      if (!Array.isArray(v) && keys.length && keys.every((x, i) => String(i + 1) === x)) {
        out[k] = keys.map((x) => clean(v[x]));
      } else {
        out[k] = clean(v);
      }
    } else {
      out[k] = v;
    }
  }
  return out;
}

function call(cb, ...args) {
  if (typeof cb === 'function') {
    try { cb(...args); } catch (e) { error('callback failed:', e.message); }
  }
}

function modalTemplate(m) {
  return {
    title: String(m.title || 'Form').slice(0, 45),
    components: (m.inputs || []).slice(0, 5).map((f) => ({
      type: 1,
      components: [{
        type: 4, custom_id: f.id, label: String(f.label).slice(0, 45), style: f.style === 'short' ? 1 : 2,
        required: f.required !== false, min_length: f.min || undefined, max_length: f.max || 1000,
        placeholder: f.placeholder ? String(f.placeholder).slice(0, 100) : undefined,
      }],
    })),
  };
}

function modalFor(customId) {
  for (const prefix of Object.keys(modals)) {
    if (customId.startsWith(prefix)) return modals[prefix];
  }
  return null;
}

function builtin() {
  let ws = null, seq = null, sessionId = null, resumeUrl = null, hbTimer = null, acked = true;

  async function rest(method, path, body, attempt = 0) {
    const res = await fetch(API + path, {
      method,
      headers: { Authorization: 'Bot ' + TOKEN, 'Content-Type': 'application/json', 'User-Agent': UA },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (res.status === 429 && attempt < 4) {
      const j = await res.json().catch(() => ({ retry_after: 1 }));
      await sleep(Math.ceil((j.retry_after || 1) * 1000) + 100);
      return rest(method, path, body, attempt + 1);
    }
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch (_) { data = text; }
    if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${typeof data === 'string' ? data : JSON.stringify(data)}`.slice(0, 600));
    return data;
  }

  const gsend = (op, d) => { if (ws && ws.readyState === 1) ws.send(JSON.stringify({ op, d })); };

  function heartbeat() {
    if (!acked) {
      warn('Heartbeat not acknowledged, reconnecting...');
      try { ws.close(4000); } catch (_) {}
      return;
    }
    acked = false;
    gsend(1, seq);
  }

  async function respond(i, type, data) {
    await rest('POST', `/interactions/${i.id}/${i.token}/callback`, data === undefined ? { type } : { type, data });
  }

  async function onInteraction(i) {
    const member = i.member || {};
    const user = member.user || i.user || {};
    const base = {
      id: i.id, token: i.token, appId: i.application_id, guildId: i.guild_id || '', channelId: i.channel_id || '',
      messageId: (i.message && i.message.id) || '', userId: user.id || '', userName: user.username || '',
      roles: member.roles || [],
    };
    if (i.type === 3) {
      const cid = i.data.custom_id || '';
      const modal = modalFor(cid);
      if (modal) {
        await respond(i, 9, { custom_id: cid + ':m', ...modalTemplate(modal) });
        return;
      }
      await respond(i, 6);
      emit('bp_discord:interaction', { ...base, kind: 'button', customId: cid, values: i.data.values || [] });
    } else if (i.type === 5) {
      const fields = {};
      for (const row of i.data.components || []) {
        for (const c of row.components || (row.component ? [row.component] : [])) fields[c.custom_id] = c.value;
      }
      await respond(i, 6);
      emit('bp_discord:interaction', { ...base, kind: 'modal', customId: i.data.custom_id || '', fields });
    } else if (i.type === 2) {
      await respond(i, 5, { flags: 64 });
      const options = {};
      for (const o of i.data.options || []) options[o.name] = o.value;
      emit('bp_discord:interaction', { ...base, kind: 'command', command: i.data.name, options });
    }
  }

  function dispatch(t, d) {
    if (t === 'READY') {
      sessionId = d.session_id;
      resumeUrl = d.resume_gateway_url;
      appId = d.application && d.application.id;
      ready = true;
      log(`${C.ok}Connected as ${d.user ? d.user.username : 'bot'}${C.reset} (builtin bot)`);
      emit('bp_discord:ready');
    } else if (t === 'RESUMED') {
      ready = true;
    } else if (t === 'INTERACTION_CREATE') {
      onInteraction(d).catch((e) => error('Interaction failed:', e.message));
    }
  }

  async function connect() {
    if (stopped) return;
    let url = resumeUrl;
    if (!url) {
      try {
        url = (await rest('GET', '/gateway/bot')).url;
      } catch (e) {
        error('Could not reach Discord:', e.message);
        if (/401/.test(e.message)) { error('The bot token is wrong. Check bp_discord_token in server.cfg.'); return; }
        setTimeout(connect, 15000);
        return;
      }
    }
    ws = new WSCtor(url + '/?v=10&encoding=json');
    ws.onmessage = (ev) => {
      let p;
      try { p = JSON.parse(typeof ev.data === 'string' ? ev.data : ev.data.toString()); } catch (_) { return; }
      if (p.s !== null && p.s !== undefined) seq = p.s;
      switch (p.op) {
        case 10: {
          clearInterval(hbTimer);
          acked = true;
          const iv = p.d.heartbeat_interval;
          setTimeout(heartbeat, Math.floor(iv * Math.random()));
          hbTimer = setInterval(heartbeat, iv);
          if (sessionId && seq !== null) {
            gsend(6, { token: TOKEN, session_id: sessionId, seq });
          } else {
            gsend(2, {
              token: TOKEN, intents: 0,
              properties: { os: 'linux', browser: 'bp_discord', device: 'bp_discord' },
              presence: { status: 'online', since: null, afk: false, activities: [{ name: ACTIVITY, type: 3 }] },
            });
          }
          break;
        }
        case 11: acked = true; break;
        case 1: gsend(1, seq); break;
        case 7: try { ws.close(4000); } catch (_) {} break;
        case 9:
          if (!p.d) { sessionId = null; seq = null; resumeUrl = null; }
          setTimeout(() => { try { ws.close(4000); } catch (_) {} }, 1000 + Math.random() * 4000);
          break;
        case 0: dispatch(p.t, p.d); break;
      }
    };
    ws.onclose = (ev) => {
      clearInterval(hbTimer);
      ready = false;
      const code = ev && ev.code;
      if ([4004, 4010, 4011, 4012, 4013, 4014].includes(code)) {
        error(`Discord closed the connection (${code}). ${code === 4004 ? 'The bot token is wrong.' : 'Check the bot settings.'}`);
        return;
      }
      if (!stopped) setTimeout(connect, 3000);
    };
    ws.onerror = () => {};
  }

  return {
    start() {
      if (!TOKEN) return error('No bot token. Add  set bp_discord_token "YOUR_TOKEN"  to server.cfg (above ensure bp_discord), or use mode \'custom\' in config.js.');
      connect();
    },
    stop() { clearInterval(hbTimer); try { ws && ws.close(1000); } catch (_) {} },
    send: async (ch, payload) => (await rest('POST', `/channels/${ch}/messages`, payload)).id,
    edit: async (ch, msg, payload) => { await rest('PATCH', `/channels/${ch}/messages/${msg}`, payload); return true; },
    dm: async (user, payload) => {
      const ch = await rest('POST', '/users/@me/channels', { recipient_id: String(user) });
      return (await rest('POST', `/channels/${ch.id}/messages`, payload)).id;
    },
    followup: async (token, payload) => {
      if (!appId) throw new Error('not connected');
      await rest('POST', `/webhooks/${appId}/${token}`, payload);
      return true;
    },
    commands: async (guildId, commands) => (await rest('PUT', `/applications/${appId}/guilds/${guildId}/commands`, commands) || []).length,
    sync() {},
  };
}

function custom() {
  let ws = null, nextId = 1, pingTimer = null, retry = 2000;
  const pending = new Map();

  const out = (msg) => { if (ws && ws.readyState === 1) ws.send(JSON.stringify(msg)); };

  function sync() {
    if (!ready) return;
    const tpl = {};
    for (const [prefix, m] of Object.entries(modals)) tpl[prefix] = modalTemplate(m);
    out({ type: 'sync', prefixes: [...claims], modals: tpl });
  }

  function rpc(method, args) {
    return new Promise((resolve, reject) => {
      if (!ready) return reject(new Error('your bot\'s bridge is not connected'));
      const id = nextId++;
      const t = setTimeout(() => { pending.delete(id); reject(new Error(`${method} timed out`)); }, 15000);
      pending.set(id, { resolve, reject, t });
      out({ type: 'call', id, method, args });
    });
  }

  function failAll(reason) {
    for (const [id, p] of pending) { clearTimeout(p.t); p.reject(new Error(reason)); pending.delete(id); }
  }

  function connect() {
    if (stopped) return;
    try {
      ws = new WSCtor(CUSTOM_URL);
    } catch (e) {
      error('Invalid custom url in config.js:', CUSTOM_URL);
      return;
    }
    ws.onopen = () => out({ type: 'auth', secret: SECRET, resource: RES, version: '1.1' });
    ws.onmessage = (ev) => {
      let m;
      try { m = JSON.parse(typeof ev.data === 'string' ? ev.data : ev.data.toString()); } catch (_) { return; }
      if (m.type === 'ready') {
        ready = true;
        retry = 2000;
        appId = m.appId || null;
        log(`${C.ok}Connected to your bot ${m.bot || ''}${C.reset} (custom bot via ${CUSTOM_URL})`);
        sync();
        clearInterval(pingTimer);
        pingTimer = setInterval(() => out({ type: 'ping' }), 30000);
        emit('bp_discord:ready');
      } else if (m.type === 'denied') {
        error('Your bot refused the connection:', m.reason || 'wrong secret', '- bp_discord_secret must match BP_BRIDGE_SECRET.');
        stopped = true;
      } else if (m.type === 'result') {
        const p = pending.get(m.id);
        if (!p) return;
        clearTimeout(p.t);
        pending.delete(m.id);
        if (m.ok) p.resolve(m.result); else p.reject(new Error(m.error || 'failed'));
      } else if (m.type === 'interaction' && m.data) {
        emit('bp_discord:interaction', m.data);
      }
    };
    ws.onclose = () => {
      const was = ready;
      ready = false;
      clearInterval(pingTimer);
      failAll('connection to your bot closed');
      if (stopped) return;
      if (was) warn('Lost connection to your bot, reconnecting...');
      setTimeout(connect, retry);
      retry = Math.min(retry * 2, 30000);
    };
    ws.onerror = () => {
      if (!ready && retry >= 16000) warn(`Can't reach your bot at ${CUSTOM_URL}. Is the bridge loaded and the port open?`);
    };
  }

  return {
    start() {
      if (SECRET.length < 16) return error('Custom mode needs  set bp_discord_secret "..."  in server.cfg (16+ characters, same as BP_BRIDGE_SECRET on your bot).');
      log(`Custom mode: connecting to your bot at ${CUSTOM_URL} ...`);
      connect();
    },
    stop() { clearInterval(pingTimer); try { ws && ws.close(1000); } catch (_) {} },
    send: (ch, payload) => rpc('send', { channelId: String(ch), payload }),
    edit: (ch, msg, payload) => rpc('edit', { channelId: String(ch), messageId: String(msg), payload }),
    dm: (user, payload) => rpc('dm', { userId: String(user), payload }),
    followup: (token, payload) => rpc('followup', { token, payload }),
    commands: async () => { throw new Error('slash commands are not available in custom mode, add them to your own bot'); },
    sync,
  };
}

const T = MODE === 'custom' ? custom() : builtin();

exports('isReady', () => ready);
exports('mode', () => MODE);

exports('send', (channelId, payload, cb) => {
  if (!channelId) return call(cb, null, 'no channel id');
  T.send(String(channelId), clean(payload))
    .then((id) => call(cb, id, null))
    .catch((e) => { error(e.message); call(cb, null, e.message); });
});

exports('edit', (channelId, messageId, payload, cb) => {
  T.edit(String(channelId), String(messageId), clean(payload))
    .then(() => call(cb, true, null))
    .catch((e) => { error(e.message); call(cb, false, e.message); });
});

exports('followup', (token, payload, cb) => {
  T.followup(token, clean(payload))
    .then(() => call(cb, true, null))
    .catch((e) => { error(e.message); call(cb, false, e.message); });
});

exports('dm', (userId, payload, cb) => {
  if (!userId) return call(cb, null, 'no user id');
  T.dm(String(userId), clean(payload))
    .then((id) => call(cb, id, null))
    .catch((e) => call(cb, null, e.message));
});

exports('claim', (prefix) => { claims.add(String(prefix)); T.sync(); });

exports('registerModal', (prefix, modal) => {
  modals[prefix] = clean(modal);
  claims.add(String(prefix));
  T.sync();
});

exports('registerCommands', (guildId, commands, cb) => {
  const go = () => T.commands(guildId, clean(commands)).then((n) => call(cb, n, null)).catch((e) => { error(e.message); call(cb, 0, e.message); });
  if (ready) go(); else on('bp_discord:ready', go);
});

if (typeof fetch !== 'function' || !WSCtor) {
  error("This resource needs Node 22. Update your FXServer artifacts (fxmanifest uses node_version '22').");
} else {
  T.start();
}

on('onResourceStop', (name) => {
  if (name !== RES) return;
  stopped = true;
  T.stop();
});
