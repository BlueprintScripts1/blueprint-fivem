Config = {}

-- ───────────────────────── Server info ─────────────────────────
-- Name shown on the panel. Empty = uses sv_projectName / sv_hostname from server.cfg
Config.ServerName = ''
-- Your connect link (shows a "Connect" button). Example: 'https://cfx.re/join/abc123'. Empty = no button
Config.ConnectUrl = ''

-- ───────────────────────── Live status panels ─────────────────────────
-- One message per channel that keeps updating itself. Add as many as you want, in any Discord server the bot is in.
--   channel   = Discord channel ID
--   jobs      = which jobs this panel lists (names from Config.Jobs). Empty = all of them
--   showNames = list who is on duty (true) or only show the count (false)
Config.Panels = {
    { channel = '000000000000000000', jobs = {}, showNames = true },
    -- { channel = '111111111111111111', jobs = { 'police' }, showNames = true },     -- e.g. in the police Discord
    -- { channel = '222222222222222222', jobs = { 'ambulance' }, showNames = true },  -- e.g. in the EMS Discord
}

Config.UpdateSeconds = 60     -- panels refresh this often (and a few seconds after anyone goes on/off duty)
Config.RefreshCooldown = 15   -- seconds between presses of the Refresh button
Config.Colors = { online = 0x22C55E, offline = 0xEF4444, duty = 0x3B82F6, offduty = 0x64748B }

-- ───────────────────────── Duty tracking ─────────────────────────
-- Jobs that are tracked. Shifts are saved to SQL and logged.
--   logs = Discord channel ID for this job's on/off duty logs (empty = no logs for this job)
Config.Jobs = {
    police    = { label = 'Police',   emoji = '🚓', logs = '' },
    ambulance = { label = 'EMS',      emoji = '🚑', logs = '' },
    mechanic  = { label = 'Mechanic', emoji = '🔧', logs = '' },
}

-- Every on/off duty is ALSO logged here (empty = off)
Config.LogsChannel = ''

Config.PollSeconds = 5        -- how often duty is double-checked (catches every duty script)
Config.MaxNames = 15          -- max names listed per job on a panel

-- ───────────────────────── Departments (set in-game) ─────────────────────────
-- /dutysettings lets each department set its OWN Discord channels in-game, e.g. in the police or EMS Discord:
--   logs channel  = on/off duty logs for that department
--   panel channel = a live panel showing only that department
-- Saved in SQL (bp_status_departments). These work on top of Config.Panels / Config.Jobs logs above.
-- 'boss'  = admins for every department + each department's bosses for their own
-- 'admin' = admins only
Config.DeptAccess = 'boss'
Config.AdminPermissions = { 'god', 'admin' } -- QBCore permissions (ace 'bp_status.admin' also works)

-- ───────────────────────── In-game ─────────────────────────
Config.DutyTimeCommand = 'dutytime'        -- shows your duty hours for the last 7 days (per character)
Config.SettingsCommand = 'dutysettings'    -- department channels menu
