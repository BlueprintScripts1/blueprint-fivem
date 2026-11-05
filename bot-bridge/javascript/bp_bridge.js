'use strict';

const crypto = require('crypto');
const { WebSocketServer } = require('ws');

const API = 'https://discord.com/api/v10';
const DEFAULT_PREFIXES = ['bpjobs:', 'bpduty:', 'bpboss:', 'bpstatus:'];
const METHODS = new Set(['send', 'edit', 'dm', 'followup']);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

module.exports = function bpBridge(client, options = {}) {
  const cfg = {
    host: options.host || process.env.BP_BRIDGE_HOST || '0.0.0.0',
    port: Number(options.port || process.env.BP_BRIDGE_PORT || 30125),
    secret: String(options.secret || process.env.BP_BRIDGE_SECRET || ''),
    offlineMessage: options.offlineMessage || process.env.BP_BRIDGE_OFFLINE_MESSAGE || 'The FiveM server is offline right now, try again in a moment.',
  };
  if (cfg.secret.length < 16) {
    console.error('[bp_bridge] BP_BRIDGE_SECRET is missing or shorter than 16 characters. Bridge not started.');
    return null;
  }

  let fivem = null;
  let prefixes = new Set(DEFAULT_PREFIXES);
  let modals = {};

  async function rest(method, path, body, auth = true, attempt = 0) {
    const headers = { 'Content-Type': 'application/json', 'User-Agent': 'DiscordBot (bp_bridge, 1.1)' };
    if (auth) headers.Authorization = 'Bot ' + client.token;
    const res = await fetch(API + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    if (res.status === 429 && attempt < 4) {
      const j = await res.json().catch(() => ({ retry_after: 1 }));
      await sleep(Math.ceil((j.retry_after || 1) * 1000) + 100);
      return rest(method, path, body, auth, attempt + 1);
    }
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${text.slice(0, 400)}`);
    return text ? JSON.parse(text) : null;
  }

  async function runCall(method, a) {
    if (method === 'send') return (await rest('POST', `/channels/${a.channelId}/messages`, a.payload)).id;
    if (method === 'edit') { await rest('PATCH', `/channels/${a.channelId}/messages/${a.messageId}`, a.payload); return true; }
    if (method === 'dm') {
      const ch = await rest('POST', '/users/@me/channels', { recipient_id: a.userId });
      return (await rest('POST', `/channels/${ch.id}/messages`, a.payload)).id;
    }
    if (method === 'followup') { await rest('POST', `/webhooks/${client.application.id}/${a.token}`, a.payload, false); return true; }
  }

  const sendTo = (ws, msg) => { if (ws && ws.readyState === 1) ws.send(JSON.stringify(msg)); };

  const wss = new WebSocketServer({ host: cfg.host, port: cfg.port, maxPayload: 2 * 1024 * 1024 });
  console.log(`[bp_bridge] Listening on ${cfg.host}:${cfg.port}`);

  wss.on('connection', (ws, req) => {
    let authed = false;
    const remote = req.socket.remoteAddress;
    const authTimer = setTimeout(() => { if (!authed) ws.close(); }, 10000);
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    ws.on('message', async (raw) => {
      let m;
      try { m = JSON.parse(raw.toString()); } catch (_) { return; }

      if (!authed) {
        clearTimeout(authTimer);
        if (m.type !== 'auth' || !safeEqual(m.secret || '', cfg.secret)) {
          console.warn(`[bp_bridge] Refused a connection from ${remote} (wrong secret)`);
          sendTo(ws, { type: 'denied', reason: 'wrong secret' });
          return ws.close();
        }
        authed = true;
        if (fivem && fivem !== ws) fivem.close(4001, 'replaced');
        fivem = ws;
        while (!client.isReady()) await sleep(500);
        sendTo(ws, { type: 'ready', bot: client.user.tag, appId: client.application.id });
        console.log(`[bp_bridge] FiveM server connected from ${remote}`);
        return;
      }

      if (m.type === 'call' && METHODS.has(m.method)) {
        runCall(m.method, m.args || {})
          .then((result) => sendTo(ws, { type: 'result', id: m.id, ok: true, result }))
          .catch((e) => sendTo(ws, { type: 'result', id: m.id, ok: false, error: String(e.message).slice(0, 500) }));
      } else if (m.type === 'sync') {
        prefixes = new Set([...DEFAULT_PREFIXES, ...(m.prefixes || []).map(String)]);
        modals = m.modals || {};
      } else if (m.type === 'ping') {
        sendTo(ws, { type: 'pong' });
      }
    });

    ws.on('close', () => {
      clearTimeout(authTimer);
      if (fivem === ws) { fivem = null; console.log('[bp_bridge] FiveM server disconnected'); }
    });
  });

  const keepAlive = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.isAlive) { ws.terminate(); continue; }
      ws.isAlive = false;
      ws.ping();
    }
  }, 30000);
  wss.on('close', () => clearInterval(keepAlive));

  const owned = (cid) => [...prefixes].some((p) => cid.startsWith(p)) || Object.keys(modals).some((p) => cid.startsWith(p));

  client.on('interactionCreate', async (interaction) => {
    const isComponent = interaction.isButton() || interaction.isAnySelectMenu();
    if (!isComponent && !interaction.isModalSubmit()) return;
    const cid = interaction.customId || '';
    if (!owned(cid)) return;
    const callback = `/interactions/${interaction.id}/${interaction.token}/callback`;

    try {
      if (isComponent) {
        const key = Object.keys(modals).find((p) => cid.startsWith(p));
        if (key) return await rest('POST', callback, { type: 9, data: { ...modals[key], custom_id: cid + ':m' } }, false);
      }
      await rest('POST', callback, { type: 6 }, false);

      if (!fivem || fivem.readyState !== 1) {
        return await rest('POST', `/webhooks/${client.application.id}/${interaction.token}`, { content: cfg.offlineMessage, flags: 64 }, false);
      }

      const fields = {};
      if (interaction.isModalSubmit()) interaction.fields.fields.forEach((f) => { fields[f.customId] = f.value; });
      const member = interaction.member;
      const roles = member && member.roles ? (member.roles.cache ? [...member.roles.cache.keys()] : member.roles) : [];

      sendTo(fivem, {
        type: 'interaction',
        data: {
          id: interaction.id, token: interaction.token, appId: interaction.applicationId,
          guildId: interaction.guildId || '', channelId: interaction.channelId || '',
          messageId: interaction.message ? interaction.message.id : '',
          userId: interaction.user.id, userName: interaction.user.username, roles: roles.map(String),
          kind: isComponent ? 'button' : 'modal', customId: cid,
          values: interaction.values || [], fields,
        },
      });
    } catch (e) {
      console.error('[bp_bridge] interaction failed:', e.message);
    }
  });

  return { close: () => { clearInterval(keepAlive); wss.close(); } };
};
