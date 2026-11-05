# Bot Bridge: use your own Discord bot

By default `bp_discord` runs its own bot inside the FiveM server. If you'd rather use **your existing bot** (discord.py or discord.js), add this bridge to it. Your bot then posts the applications, handles the buttons, and works for every Blueprint resource. `bp_discord` becomes a small API that talks to your bot.

```
 FiveM server                                   Your bot
┌─────────────┐   ┌────────────┐   WebSocket   ┌──────────────────┐        ┌─────────┐
│ bp_jobs     ├──►│ bp_discord ├──────────────►│ bp_bridge (port) ├───────►│ Discord │
│ bp_duty ... │◄──┤  (custom)  │◄──────────────┤ cog / module     │◄───────┤         │
└─────────────┘   └────────────┘  secret-auth  └──────────────────┘        └─────────┘
```

## When can I use it?
Your bot must be reachable from the FiveM server on one TCP port:
- **The bot runs on the same machine (or VPS) as FiveM:** use `ws://127.0.0.1:30125`. Nothing to open.
- **The bot is on a bot host with port forwarding / extra allocations** (Pterodactyl, Pelican, most game panels): give the bot an extra port, then use `ws://HOST_IP:THAT_PORT`.
- **Bot hosts with no open ports** (some free hosts): this won't work. Use builtin mode instead.

The bot keeps working normally. The bridge only handles buttons that start with `bpjobs:`, `bpduty:`, `bpboss:` or `bpstatus:`, so your own buttons and commands are untouched.

---

## 1. Pick a secret
Make a long random string (16+ characters), for example from a password generator. The same secret goes on both sides.

## 2a. discord.py (Python)
Requires discord.py 2.x (aiohttp comes with it).

1. Copy `python/bp_bridge.py` into your bot folder, next to your main file (or into your `cogs` folder).
2. Load it like any cog:
```python
await bot.load_extension("bp_bridge")        # or "cogs.bp_bridge"
```
3. Set these environment variables (in a `.env` file loaded with python-dotenv, or the panel's variables / startup settings):

| Variable | Default | What |
|---|---|---|
| `BP_BRIDGE_SECRET` | – | **Required.** The secret from step 1 |
| `BP_BRIDGE_PORT` | `30125` | Port to listen on. On a panel, use the extra port you allocated |
| `BP_BRIDGE_HOST` | `0.0.0.0` | `127.0.0.1` if FiveM is on the same machine (more secure) |
| `BP_BRIDGE_OFFLINE_MESSAGE` | | Shown when someone clicks while FiveM is offline |

No env support? Edit the defaults in the `SETTINGS` block at the top of `bp_bridge.py`.

The console prints `[bp_bridge] Listening on 0.0.0.0:30125`.

## 2b. discord.js (JavaScript)
Requires discord.js v14 and Node 18+.

1. `npm install ws`
2. Copy `javascript/bp_bridge.js` into your bot folder.
3. In your main file, after creating the client:
```js
const bpBridge = require('./bp_bridge');

bpBridge(client, {
  secret: process.env.BP_BRIDGE_SECRET,   // required, 16+ characters
  port: 30125,                            // optional, default 30125 (or BP_BRIDGE_PORT)
  host: '0.0.0.0',                        // optional, '127.0.0.1' if FiveM is on the same machine
});
```
The options can also come from the same environment variables as the Python table.

Your client needs the `Guilds` intent (every bot has it).

## 3. FiveM side
In `bp_discord/config.js`:
```js
mode: 'custom',
custom: { url: 'ws://127.0.0.1:30125' },    // or ws://BOT_HOST_IP:PORT
```
In `server.cfg`:
```cfg
set bp_discord_secret "the-same-secret-as-BP_BRIDGE_SECRET"
ensure bp_discord
```
You don't need `bp_discord_token` in custom mode.

The FiveM console should print:
```
[bp_discord] Connected to your bot MyBot#1234 (custom bot via ws://127.0.0.1:30125)
```
and your bot prints `[bp_bridge] FiveM server connected`.

## 4. Invite / permissions
Your bot needs **View Channels, Send Messages, Embed Links, Read Message History** in every applications and logs channel. It must also be in every Discord server you use (police Discord, EMS Discord...).

---

## Security
- Connections without the right secret are refused and logged.
- Your bot token **never** leaves your bot. FiveM only asks it to send, edit or DM messages and to answer buttons.
- Use `BP_BRIDGE_HOST=127.0.0.1` when both run on the same machine. When using port forwarding, use a long secret and only allocate the one port.
- One FiveM server per bridge: if a second one connects with the right secret, it replaces the first.

## Troubleshooting
| Message | Fix |
|---|---|
| FiveM: `Can't reach your bot at ws://...` | Bot not running, wrong IP/port, port not allocated on the panel, or a firewall is blocking it |
| FiveM: `Your bot refused the connection: wrong secret` | `bp_discord_secret` and `BP_BRIDGE_SECRET` must be exactly the same |
| Bot: `BP_BRIDGE_SECRET is missing or shorter than 16 characters` | Set the variable, or edit `SETTINGS` / pass `secret` |
| Bot: `address already in use` | Another program uses that port. Pick another and change both sides |
| Clickers see "The FiveM server is offline" | The bot is fine, but FiveM isn't connected right now. It reconnects automatically |

## Other languages
The protocol is small JSON over a WebSocket, so you can port it to any bot. Read `python/bp_bridge.py` as the reference:
1. `auth`, then `ready`
2. `sync`: prefixes and modals
3. `call` / `result`: send, edit, dm, followup
4. `interaction`: pushed to FiveM
