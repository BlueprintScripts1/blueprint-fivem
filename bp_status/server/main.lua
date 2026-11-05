local QBCore = exports['qb-core']:GetCoreObject()
local startedAt = os.time()
local active = {}
local dirty = false
local lastRefresh = 0
local offline = false
local Dept = {}
local logQueue = {}

local function realChannel(c) c = tostring(c or '') return c:match('^%d+$') ~= nil and #c >= 17 and #c <= 20 and c ~= '000000000000000000' end

local function await(fn)
    local p, done = promise.new(), false
    local function finish(a, b) if not done then done = true p:resolve({ a, b }) end end
    local ok, err = pcall(fn, finish)
    if not ok then return nil, tostring(err) end
    SetTimeout(20000, function() finish(nil, 'timeout') end)
    local r = Citizen.Await(p)
    return r[1], r[2]
end

local function dsend(ch, payload) return await(function(cb) exports.bp_discord:send(ch, payload, cb) end) end
local function dedit(ch, msg, payload) return await(function(cb) exports.bp_discord:edit(ch, msg, payload, cb) end) end

local function text(s) return { type = 10, content = s } end
local function sep() return { type = 14, divider = true, spacing = 1 } end
local function v2(color, parts, rows)
    local comps = { { type = 17, accent_color = color, components = parts } }
    for _, r in ipairs(rows or {}) do comps[#comps + 1] = r end
    return { flags = 32768, allowed_mentions = { parse = {} }, components = comps }
end

local function serverName()
    local n = Config.ServerName ~= '' and Config.ServerName or GetConvar('sv_projectName', '')
    if n == '' then n = GetConvar('sv_hostname', 'FiveM Server') end
    return (n:gsub('%^%d', ''):gsub('[*_`~|]', ''))
end

local function duration(sec)
    sec = math.max(0, math.floor(sec))
    local h, m = sec // 3600, (sec % 3600) // 60
    if h > 0 then return ('%dh %dm'):format(h, m) end
    return ('%dm'):format(m)
end

local function charName(P)
    local c = P.PlayerData.charinfo or {}
    local n = ((c.firstname or '') .. ' ' .. (c.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if n == '' then n = GetPlayerName(P.PlayerData.source) or 'Unknown' end
    return n
end

local function safe(s) return (tostring(s):gsub('[*_`~|>@]', '')) end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bp_duty_shifts` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, `citizenid` VARCHAR(64) NOT NULL, `name` VARCHAR(100) NULL,
        `job` VARCHAR(50) NOT NULL, `grade` INT NOT NULL DEFAULT 0, `grade_name` VARCHAR(60) NULL,
        `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, `last_seen` TIMESTAMP NULL, `ended_at` TIMESTAMP NULL,
        `seconds` INT NULL, `end_reason` VARCHAR(20) NULL,
        INDEX `cid_job` (`citizenid`, `job`), INDEX `open` (`ended_at`))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bp_status_departments` (
        `job` VARCHAR(50) NOT NULL PRIMARY KEY, `logs_channel` VARCHAR(30) NULL, `panel_channel` VARCHAR(30) NULL,
        `show_names` TINYINT(1) NOT NULL DEFAULT 1, `updated_by` VARCHAR(100) NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)]])
    for _, r in ipairs(MySQL.query.await('SELECT * FROM bp_status_departments') or {}) do
        Dept[r.job] = { logs = r.logs_channel, panel = r.panel_channel, showNames = r.show_names == 1 or r.show_names == true }
    end
    MySQL.update.await([[UPDATE bp_duty_shifts SET ended_at = COALESCE(last_seen, started_at),
        seconds = TIMESTAMPDIFF(SECOND, started_at, COALESCE(last_seen, started_at)), end_reason = 'restart' WHERE ended_at IS NULL]])
end)

local function log(job, line)
    local payload = v2(Config.Colors.duty, { text(line .. '\n-# ' .. os.date('%Y-%m-%d %H:%M')) })
    local targets = {}
    if realChannel(Config.LogsChannel) then targets[Config.LogsChannel] = true end
    local j = Config.Jobs[job]
    if j and realChannel(j.logs) then targets[j.logs] = true end
    local d = Dept[job]
    if d and realChannel(d.logs) then targets[d.logs] = true end
    for ch in pairs(targets) do logQueue[#logQueue + 1] = { ch, payload } end
end

CreateThread(function()
    while true do
        local item = table.remove(logQueue, 1)
        if item then dsend(item[1], item[2]) else Wait(250) end
    end
end)

local function startShift(src, P, silent)
    local job = P.PlayerData.job
    local cfg = Config.Jobs[job.name]
    local s = {
        cid = P.PlayerData.citizenid, name = charName(P), job = job.name, grade = tonumber(job.grade and job.grade.level) or 0,
        gradeName = job.grade and job.grade.name or '', start = os.time(),
    }
    active[src] = s
    s.id = MySQL.insert.await('INSERT INTO bp_duty_shifts (citizenid, name, job, grade, grade_name, last_seen) VALUES (?, ?, ?, ?, ?, NOW())',
        { s.cid, s.name, s.job, s.grade, s.gradeName })
    dirty = true
    if not silent then
        log(s.job, ('🟢 **%s** went **on duty** · %s %s · %s'):format(safe(s.name), cfg.emoji, cfg.label, safe(s.gradeName)))
    end
end

local function endShift(src, reason)
    local s = active[src]
    if not s then return end
    active[src] = nil
    local secs = os.time() - s.start
    if s.id then
        MySQL.update('UPDATE bp_duty_shifts SET ended_at = NOW(), last_seen = NOW(), seconds = ?, end_reason = ? WHERE id = ?', { secs, reason, s.id })
    end
    dirty = true
    local cfg = Config.Jobs[s.job] or { emoji = '', label = s.job }
    local why = ({ disconnected = ' (left the server)', job_change = ' (changed job)', logout = ' (logged out)',
        char_change = ' (switched character)', shutdown = ' (server shutdown)' })[reason] or ''
    log(s.job, ('🔴 **%s** went **off duty**%s · %s %s · shift **%s**'):format(safe(s.name), why, cfg.emoji, cfg.label, duration(secs)))
end

local function goneReason(src) return GetPlayerName(src) and 'logout' or 'disconnected' end

local function reconcile(src, silent)
    local P = QBCore.Functions.GetPlayer(src)
    local s = active[src]
    if s and (not P or P.PlayerData.citizenid ~= s.cid) then
        endShift(src, P and 'char_change' or goneReason(src))
        s = nil
    end
    if not P then return end
    local job = P.PlayerData.job or {}
    local onDuty = Config.Jobs[job.name] ~= nil and job.onduty == true
    if s and (not onDuty or s.job ~= job.name) then
        endShift(src, s.job ~= job.name and 'job_change' or 'off_duty')
        s = nil
    end
    if onDuty and not s then startShift(src, P, silent) end
end

local function reconcileAll(silent)
    local seen = {}
    for _, P in pairs(QBCore.Functions.GetQBPlayers()) do
        local src = P.PlayerData.source
        seen[src] = true
        reconcile(src, silent)
    end
    for src in pairs(active) do if not seen[src] then endShift(src, goneReason(src)) end end
end

AddEventHandler('QBCore:Server:SetDuty', function(src) SetTimeout(250, function() reconcile(src) end) end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src) SetTimeout(250, function() reconcile(src) end) end)
AddEventHandler('playerDropped', function() endShift(source, 'disconnected') end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) endShift(src, 'logout') end)

local function onDutyList(jobs)
    local by = {}
    for _, s in pairs(active) do
        by[s.job] = by[s.job] or {}
        table.insert(by[s.job], s)
    end
    local order = {}
    if jobs and #jobs > 0 then order = jobs else
        for name in pairs(Config.Jobs) do order[#order + 1] = name end
        table.sort(order, function(a, b) return Config.Jobs[a].label < Config.Jobs[b].label end)
    end
    return order, by
end

local function panelPayload(panel)
    if offline then
        return v2(Config.Colors.offline, {
            text(('## 🔴 %s'):format(serverName())),
            text(('**Status:** Offline\n-# Since <t:%d:R>'):format(os.time())),
        })
    end
    local players = #GetPlayers()
    local maxPlayers = GetConvarInt('sv_maxclients', 48)
    local parts = {
        text(('## 🟢 %s'):format(serverName())),
        text(('**Status:** Online   ·   **Players:** %d/%d   ·   **Uptime:** %s'):format(players, maxPlayers, duration(os.time() - startedAt))),
        sep(),
    }
    local order, by = onDutyList(panel.jobs)
    local lines = { '### On duty' }
    for _, name in ipairs(order) do
        local cfg = Config.Jobs[name]
        if cfg then
            local list = by[name] or {}
            table.sort(list, function(a, b) return a.grade > b.grade end)
            local line = ('%s **%s** · %d'):format(cfg.emoji, cfg.label, #list)
            if panel.showNames and #list > 0 then
                local names = {}
                for i = 1, math.min(#list, Config.MaxNames) do
                    local s = list[i]
                    names[#names + 1] = s.gradeName ~= '' and ('%s (%s)'):format(safe(s.name), safe(s.gradeName)) or safe(s.name)
                end
                if #list > Config.MaxNames then names[#names + 1] = ('+%d more'):format(#list - Config.MaxNames) end
                line = line .. '\n> ' .. table.concat(names, ', ')
            end
            lines[#lines + 1] = line
        end
    end
    parts[#parts + 1] = text(table.concat(lines, '\n'))
    parts[#parts + 1] = sep()
    parts[#parts + 1] = text(('-# Updated <t:%d:R>'):format(os.time()))

    local buttons = { { type = 2, style = 2, label = 'Refresh', emoji = { name = '🔄' }, custom_id = 'bpstatus:refresh' } }
    if Config.ConnectUrl:match('^https://') then
        buttons[#buttons + 1] = { type = 2, style = 5, label = 'Connect', emoji = { name = '🎮' }, url = Config.ConnectUrl }
    end
    parts[#parts + 1] = { type = 1, components = buttons }
    return v2(Config.Colors.online, parts)
end

local function kvpKey(ch) return 'panel:' .. ch end

local function updatePanel(panel)
    if not realChannel(panel.channel) then return end
    local payload = panelPayload(panel)
    local msgId = GetResourceKvpString(kvpKey(panel.channel))
    if msgId and msgId ~= '' then
        local ok, err = dedit(panel.channel, msgId, payload)
        if ok then return end
        if not tostring(err):find('404') and not tostring(err):find('10008') then return end
    end
    local id = dsend(panel.channel, payload)
    if id then SetResourceKvp(kvpKey(panel.channel), id) end
end

local function panels()
    local byChannel, out = {}, {}
    local function add(channel, jobs, showNames)
        if not realChannel(channel) then return end
        local p = byChannel[channel]
        if not p then
            p = { channel = channel, jobs = {}, all = false, showNames = showNames }
            byChannel[channel] = p
            out[#out + 1] = p
        end
        if not jobs or #jobs == 0 then p.all = true else
            for _, j in ipairs(jobs) do
                local dup = false
                for _, x in ipairs(p.jobs) do if x == j then dup = true end end
                if not dup then p.jobs[#p.jobs + 1] = j end
            end
        end
        p.showNames = p.showNames or showNames
    end
    for _, c in ipairs(Config.Panels) do add(c.channel, c.jobs, c.showNames ~= false) end
    for job, d in pairs(Dept) do if Config.Jobs[job] then add(d.panel, { job }, d.showNames) end end
    for _, p in ipairs(out) do if p.all then p.jobs = {} end end
    return out
end

local function updateAll()
    for _, panel in ipairs(panels()) do updatePanel(panel) end
end

CreateThread(function()
    while GetResourceState('bp_discord') ~= 'started' do Wait(500) end
    exports.bp_discord:claim('bpstatus:')
    Wait(3000)
    while not exports.bp_discord:isReady() do Wait(1000) end
    reconcileAll(true)
    updateAll()
    local last = os.time()
    while true do
        Wait(Config.PollSeconds * 1000)
        reconcileAll(false)
        if os.time() - last >= Config.UpdateSeconds or (dirty and os.time() - last >= 10) then
            dirty = false
            last = os.time()
            updateAll()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        if next(active) then MySQL.update('UPDATE bp_duty_shifts SET last_seen = NOW() WHERE ended_at IS NULL') end
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res == 'bp_discord' then Wait(1000) exports.bp_discord:claim('bpstatus:') end
end)

AddEventHandler('bp_discord:interaction', function(i)
    if i.kind ~= 'button' or i.customId ~= 'bpstatus:refresh' then return end
    if os.time() - lastRefresh < Config.RefreshCooldown then return end
    lastRefresh = os.time()
    for _, panel in ipairs(panels()) do
        if panel.channel == i.channelId then CreateThread(function() updatePanel(panel) end) return end
    end
end)

local function goOffline()
    if offline then return end
    for src in pairs(active) do endShift(src, 'shutdown') end
    offline = true
    for _, panel in ipairs(panels()) do
        local msgId = realChannel(panel.channel) and GetResourceKvpString(kvpKey(panel.channel))
        if msgId and msgId ~= '' then
            pcall(function() exports.bp_discord:edit(panel.channel, msgId, panelPayload(panel), function() end) end)
        end
    end
end

AddEventHandler('txAdmin:events:serverShuttingDown', function() goOffline() end)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then goOffline() end end)

RegisterCommand(Config.DutyTimeCommand, function(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return end
    local rows = MySQL.query.await([[SELECT job, SUM(seconds) AS total, COUNT(*) AS shifts FROM bp_duty_shifts
        WHERE citizenid = ? AND ended_at IS NOT NULL AND started_at > NOW() - INTERVAL 7 DAY GROUP BY job]], { P.PlayerData.citizenid }) or {}
    local totals = {}
    for _, r in ipairs(rows) do totals[r.job] = { secs = tonumber(r.total) or 0, shifts = tonumber(r.shifts) or 0 } end
    local s = active[src]
    if s then
        totals[s.job] = totals[s.job] or { secs = 0, shifts = 0 }
        totals[s.job].secs = totals[s.job].secs + (os.time() - s.start)
        totals[s.job].shifts = totals[s.job].shifts + 1
    end
    local parts = {}
    for job, t in pairs(totals) do
        parts[#parts + 1] = ('%s: %s (%d %s)'):format((Config.Jobs[job] or { label = job }).label, duration(t.secs), t.shifts, t.shifts == 1 and 'shift' or 'shifts')
    end
    local msg = #parts > 0 and ('Last 7 days · ' .. table.concat(parts, ' · ')) or 'No duty time in the last 7 days.'
    TriggerClientEvent('QBCore:Notify', src, msg, 'primary', 10000)
end, false)

exports('GetOnDuty', function(job)
    local out = {}
    for src, s in pairs(active) do
        if not job or s.job == job then out[#out + 1] = { source = src, citizenid = s.cid, name = s.name, job = s.job, grade = s.grade, since = s.start } end
    end
    return out
end)

exports('CountOnDuty', function(job)
    local n = 0
    for _, s in pairs(active) do if s.job == job then n = n + 1 end end
    return n
end)

local function isAdmin(src)
    if src == 0 or IsPlayerAceAllowed(src, 'bp_status.admin') then return true end
    for _, perm in ipairs(Config.AdminPermissions) do
        if QBCore.Functions.HasPermission(src, perm) then return true end
    end
    return false
end

local function canEdit(src, job)
    if not Config.Jobs[job] then return false end
    if isAdmin(src) then return true end
    if Config.DeptAccess ~= 'boss' then return false end
    local P = QBCore.Functions.GetPlayer(src)
    local j = P and P.PlayerData.job
    return j ~= nil and j.isboss == true and j.name == job
end

local function actor(src)
    local P = QBCore.Functions.GetPlayer(src)
    return P and ('%s (%s)'):format(charName(P), GetPlayerName(src)) or (GetPlayerName(src) or 'console')
end

lib.callback.register('bp_status:departments', function(src)
    local out = {}
    for job, cfg in pairs(Config.Jobs) do
        if canEdit(src, job) then
            local d = Dept[job] or {}
            out[#out + 1] = { job = job, label = cfg.label, emoji = cfg.emoji, logs = d.logs, panel = d.panel,
                showNames = d.showNames ~= false, configLogs = realChannel(cfg.logs) and cfg.logs or nil }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

lib.callback.register('bp_status:saveDepartment', function(src, job, data)
    if not canEdit(src, job) or type(data) ~= 'table' then return { ok = false, reason = 'No access.' } end
    local logs = tostring(data.logs or ''):gsub('%s', '')
    local panel = tostring(data.panel or ''):gsub('%s', '')
    if logs ~= '' and not realChannel(logs) then return { ok = false, reason = 'Logs channel ID must be 17-20 digits.' } end
    if panel ~= '' and not realChannel(panel) then return { ok = false, reason = 'Panel channel ID must be 17-20 digits.' } end
    local old = Dept[job] or {}
    local d = { logs = logs ~= '' and logs or nil, panel = panel ~= '' and panel or nil, showNames = data.showNames ~= false }

    if old.panel and old.panel ~= d.panel then
        local stillUsed = false
        for j, x in pairs(Dept) do if j ~= job and x.panel == old.panel then stillUsed = true end end
        for _, c in ipairs(Config.Panels) do if c.channel == old.panel then stillUsed = true end end
        local msgId = GetResourceKvpString(kvpKey(old.panel))
        if not stillUsed and msgId and msgId ~= '' then
            local note = d.panel and ('This panel moved to <#%s>.'):format(d.panel) or 'This panel was turned off.'
            CreateThread(function() dedit(old.panel, msgId, v2(Config.Colors.offduty, { text('-# ' .. note) })) end)
            DeleteResourceKvp(kvpKey(old.panel))
        end
    end

    Dept[job] = d
    local who = actor(src)
    MySQL.insert.await([[INSERT INTO bp_status_departments (job, logs_channel, panel_channel, show_names, updated_by) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE logs_channel = VALUES(logs_channel), panel_channel = VALUES(panel_channel),
        show_names = VALUES(show_names), updated_by = VALUES(updated_by)]], { job, d.logs or '', d.panel or '', d.showNames and 1 or 0, who })
    if d.logs == nil then MySQL.update('UPDATE bp_status_departments SET logs_channel = NULL WHERE job = ? AND logs_channel = ?', { job, '' }) end
    if d.panel == nil then MySQL.update('UPDATE bp_status_departments SET panel_channel = NULL WHERE job = ? AND panel_channel = ?', { job, '' }) end

    local cfg = Config.Jobs[job]
    log(job, ('🛠️ **%s** updated %s **%s** duty settings · logs %s · panel %s'):format(safe(who), cfg.emoji, cfg.label,
        d.logs and ('<#' .. d.logs .. '>') or '*off*', d.panel and ('<#' .. d.panel .. '>') or '*off*'))
    dirty = true
    CreateThread(updateAll)
    return { ok = true }
end)

lib.callback.register('bp_status:testDepartment', function(src, job)
    if not canEdit(src, job) then return { ok = false, reason = 'No access.' } end
    local d, cfg = Dept[job] or {}, Config.Jobs[job]
    local results = {}
    for _, pair in ipairs({ { 'Logs', d.logs }, { 'Panel', d.panel } }) do
        if pair[2] then
            local id, err = dsend(pair[2], v2(Config.Colors.duty, { text(('🔔 **Test message** for %s %s (%s channel). It works!'):format(cfg.emoji, cfg.label, pair[1]:lower())) }))
            results[#results + 1] = pair[1] .. ': ' .. (id and 'OK' or ('failed (' .. tostring(err):sub(1, 80) .. ')'))
        end
    end
    if #results == 0 then return { ok = false, reason = 'No channels set yet.' } end
    return { ok = true, reason = table.concat(results, ' · ') }
end)
