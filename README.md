# bp_status: Live Server Status & Duty Tracking (QBCore · demo)

A Discord panel that updates itself: server online/offline, players, uptime, and **who is on duty** per job. Every shift is tracked, logged and saved to SQL.

Uses `bp_discord`, so it works with the **builtin bot** or **your own bot** (Bot Bridge), across **multiple Discord servers**.

> This is a demo (v0.2). QBCore only for now. Standalone, Qbox and ESX are coming, like in bp_jobs.

## Requirements
- `qb-core`, `oxmysql`, `ox_lib`
- `bp_discord` v1+ (already set up if you use bp_jobs)

## Install
1. Put `bp_status` in your resources.
2. In `server.cfg`, after bp_discord:
```cfg
ensure bp_discord
ensure bp_status
```
3. In `config.lua`:
   - Put a channel ID in `Config.Panels`.
   - Optional: `Config.ConnectUrl` (your `https://cfx.re/join/...` link) adds a **Connect** button.
4. Restart. The bot posts the panel and keeps **editing that same message**. It doesn't spam new ones.

Tip: put the panel in a read-only channel and pin it.

## The panel
```
🟢 Blueprint RP
Status: Online · Players: 23/64 · Uptime: 3h 12m
──────────────
On duty
🚑 EMS · 2
> Ana Doe (Paramedic), Mike Ross (Doctor)
🚓 Police · 4
> John Doe (Sergeant), ...
──────────────
Updated 12 seconds ago
[🔄 Refresh] [🎮 Connect]
```
- It refreshes every `Config.UpdateSeconds` (60), and a few seconds after someone goes on or off duty.
- **Refresh** updates it right away (with a 15s cooldown, so it can't be spammed).
- When the server shuts down (txAdmin restart/stop, or bp_status stopped), the panel turns **🔴 Offline**.
- If someone deletes the panel message, a new one is posted automatically.

**Multiple panels / multiple Discords:** every entry in `Config.Panels` is its own message, for example:
- one panel with all jobs in the main city Discord
- one with only `police` in the police Discord
- one with only `ambulance` in the EMS Discord

Set `showNames = false` to show only the counts.

## Departments (set in-game)
Each department can use its **own Discord**. With **/dutysettings**, a department sets:
| Setting | What |
|---|---|
| **Logs channel** | Its own on/off duty logs (e.g. `#duty-logs` in the police Discord) |
| **Panel channel** | A live panel showing **only that department** |
| **Show names** | Panel shows who is on duty, or only the count |
| **Send test message** | Checks the bot can post in both channels |

Who can use it:
- **admins:** QBCore `god`/`admin`, or the ace `bp_status.admin`. They can edit every department.
- **bosses:** with `Config.DeptAccess = 'boss'`, each department's bosses can edit their own.
- Set `Config.DeptAccess = 'admin'` for admins only.

Notes:
- This works **on top of** `Config.Panels` and the `logs` in `Config.Jobs`. Config is for the main city Discord; `/dutysettings` is for each department's own Discord.
- Two departments can point at the **same** panel channel: they're merged into one panel (e.g. a shared "Emergency Services" Discord).
- Moving a panel to another channel turns the old message into "This panel moved to #new-channel".
- Saved in SQL (`bp_status_departments`).

## Duty tracking
- Tracks the jobs in `Config.Jobs`, using QBCore's own `onduty`. It works with any duty script (MDTs, clock-in peds, `/duty`...): bp_status listens to QBCore's duty events and also double-checks every 5 seconds.
- Logs `🟢 John Doe went on duty · 🚓 Police · Sergeant` and `🔴 John Doe went off duty · shift 2h 14m` to:
  - the job's own `logs` channel
  - and/or `Config.LogsChannel` (all jobs)
- A shift ends when the player goes off duty, changes job, logs out, **switches character**, disconnects, or the server shuts down.
- **Multiple characters:** shifts belong to the **character**, not the player. If someone logs out to character select (or switches with any multicharacter script) and picks a second character, the first character's shift ends, and the second one starts its own. Hours never mix, and `/dutytime` always shows the current character's time.
- Logs go out in order, one at a time, so on/off messages never arrive mixed up.
- If the server crashes, open shifts are closed at the player's last minute online when it starts again, so nobody gets 10 fake hours.

## In-game
| Command | What |
|---|---|
| `/dutytime` | Your character's duty time and shifts per job for the last 7 days |
| `/dutysettings` | Department Discord channels (admins / bosses) |

## Exports (server)
```lua
exports.bp_status:GetOnDuty('police')    -- { { source, citizenid, name, job, grade, since }, ... }  (nil = all jobs)
exports.bp_status:CountOnDuty('ambulance') -- 3
```
Handy for other scripts, e.g. "no robberies with fewer than 4 cops on duty".

## SQL
Created automatically:
- `bp_duty_shifts`: one row per shift, with citizenid (per character), name, job, grade, start, end, seconds, and the end reason (`off_duty`, `logout`, `char_change`, `job_change`, `disconnected`, `shutdown`, `restart`).
- `bp_status_departments`: each department's logs channel, panel channel and show-names setting.

## Coming next
Weekly hours leaderboards on Discord, a boss view of employee hours, and Standalone / Qbox / ESX support.
