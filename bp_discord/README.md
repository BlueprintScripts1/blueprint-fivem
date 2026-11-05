# bp_discord

One Discord bot connection that runs **inside your FiveM server**. No VPS, no Python, no npm install.
Every Blueprint resource (applications now; duty, status and the Discord boss menu later) talks to Discord through it, so you only ever run one bot.

## Two modes (`config.js`)
| Mode | What | Needs |
|---|---|---|
| `builtin` (default) | bp_discord runs its own bot inside FiveM | `set bp_discord_token` in server.cfg |
| `custom` | Uses **your own** discord.py / discord.js bot through the Bot Bridge | the bridge added to your bot + `set bp_discord_secret` (see `bot-bridge/README.md`) |

**One bot, many Discord servers:** the bot can be in as many Discord servers as you like (main city, police, EMS...). Each ped or job just points at a channel ID in whichever server it belongs to.

The rest of this page is about **builtin** mode. For custom mode, follow `bot-bridge/README.md`.

## Requirements
- FXServer artifacts with Node 22 support (any 2025+ build). The manifest uses `node_version '22'`.
- Nothing else.

## 1. Create the bot
1. Go to the [Discord Developer Portal](https://discord.com/developers/applications) and click **New Application** (e.g. "Blueprint | City").
2. Open **Bot**, click **Reset Token**, and copy the token.
3. **Privileged intents:** leave them all off. They're not needed.
4. Open **OAuth2 → URL Generator** and set:
   - scopes: `bot` and `applications.commands`
   - permissions: **View Channels, Send Messages, Embed Links, Read Message History**
5. Open the generated link and add the bot to **every Discord server you use**. If police applications go to the police Discord and EMS to the EMS Discord, the same bot must be in both.

> Want to use a bot you already run? Don't paste its token here (two programs on one token fight over button clicks). Use **custom** mode with the Bot Bridge instead.

## 2. server.cfg
```cfg
set bp_discord_token "PASTE_TOKEN_HERE"

ensure bp_discord
```
The bot's status text ("Watching over the city") is `activity` in `config.js`.
- The `set` line must be **above** `ensure bp_discord`.
- Keep the token only in `server.cfg`. Never inside a resource you share or upload.

When it works, the console prints:
```
[bp_discord] Connected as Blueprint | City
```

## 3. What it does
- Keeps the Discord connection alive (heartbeat, auto reconnect and resume).
- Sends and edits messages (Components V2), with automatic rate-limit retries.
- Handles buttons and forms:
  - Buttons are acknowledged instantly, so Discord never shows "This interaction failed".
  - Buttons registered with a form (like **Deny** with a reason) open that form.
  - Results are passed to the resource that owns the button.
- Sends DMs (quietly skipped when the user has DMs closed).

## For developers (exports)
```lua
-- listen to buttons / forms / slash commands
AddEventHandler('bp_discord:interaction', function(i)
    -- i.kind = 'button' | 'modal' | 'command'
    -- i.customId, i.userId, i.userName, i.roles, i.fields (modal), i.values (selects),
    -- i.channelId, i.messageId, i.guildId, i.token
end)

exports.bp_discord:isReady()                                  -- true when connected
exports.bp_discord:mode()                                     -- 'builtin' or 'custom'
exports.bp_discord:claim('myres:')                            -- buttons starting with this are yours (needed for custom mode)
exports.bp_discord:send(channelId, payload, function(messageId, err) end)
exports.bp_discord:edit(channelId, messageId, payload, function(ok, err) end)
exports.bp_discord:dm(userId, payload, function(messageId, err) end)
exports.bp_discord:followup(i.token, { content = 'Only you see this', flags = 64 }, function(ok, err) end)

-- buttons whose custom_id starts with the prefix open this form; the submit arrives as kind 'modal' with customId .. ':m'
exports.bp_discord:registerModal('myres:report:', {
    title = 'Report', inputs = { { id = 'text', label = 'What happened?', style = 'paragraph', max = 500 } },
})

exports.bp_discord:registerCommands(guildId, { { name = 'status', description = 'Server status' } }, function(count, err) end)  -- builtin mode only
```
`payload` is a normal Discord message object (Lua table). Empty Lua tables for `components`, `embeds` or `allowed_mentions.parse` are fixed into arrays automatically.

## Troubleshooting
| Console message | Fix |
|---|---|
| `No bot token` | Add the `set bp_discord_token` line above `ensure bp_discord` |
| `The bot token is wrong` / `(4004)` | Reset the token in the Developer Portal and paste the new one |
| `This resource needs Node 22` | Update your FXServer artifacts |
| `POST /channels/.../messages -> 403` | The bot can't see or post in that channel. Check channel permissions, and that the bot is in that Discord |
| `-> 404 Unknown Channel` | Wrong channel ID, or the bot isn't in that Discord server |
| Custom mode errors | See the troubleshooting table in `bot-bridge/README.md` |
