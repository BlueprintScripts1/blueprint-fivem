local function db(kind, sql, params)
    local out, i = {}, 0
    local q = sql:gsub('%?', function()
        i = i + 1
        if params == nil or params[i] == nil then return 'NULL' end
        out[#out + 1] = params[i]
        return '?'
    end)
    return MySQL[kind].await(q, out)
end
local E = Config.Emojis
local Peds = {}
local Settings = {}
local busy = {}

CreateThread(function()
    db('query', [[CREATE TABLE IF NOT EXISTS `bp_identities` (
        `citizenid` VARCHAR(64) NOT NULL PRIMARY KEY, `license` VARCHAR(60) NULL, `discord` VARCHAR(30) NULL,
        `steam` VARCHAR(60) NULL, `fivem_name` VARCHAR(100) NULL, `char_name` VARCHAR(100) NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, INDEX `discord` (`discord`))]])
    db('query', [[CREATE TABLE IF NOT EXISTS `bp_application_peds` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, `job` VARCHAR(50) NOT NULL, `label` VARCHAR(60) NOT NULL,
        `model` VARCHAR(60) NOT NULL, `scenario` VARCHAR(60) NOT NULL DEFAULT 'none',
        `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `h` DOUBLE NOT NULL,
        `channel_id` VARCHAR(30) NOT NULL, `enabled` TINYINT(1) NOT NULL DEFAULT 1, `created_by` VARCHAR(50) NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)]])
    db('query', [[CREATE TABLE IF NOT EXISTS `bp_applications` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, `citizenid` VARCHAR(64) NOT NULL, `job` VARCHAR(50) NOT NULL,
        `type` VARCHAR(16) NOT NULL DEFAULT 'hire', `from_grade` INT NULL, `target_grade` INT NOT NULL DEFAULT 0,
        `ped_id` INT NULL, `char_name` VARCHAR(100) NULL, `fivem_name` VARCHAR(100) NULL, `discord` VARCHAR(30) NULL,
        `steam` VARCHAR(60) NULL, `steam64` VARCHAR(30) NULL, `license` VARCHAR(60) NULL, `phone` VARCHAR(30) NULL,
        `current_job` VARCHAR(50) NULL, `current_grade` INT NULL, `answers` LONGTEXT NULL,
        `status` VARCHAR(16) NOT NULL DEFAULT 'pending', `reason` TEXT NULL, `decided_by` VARCHAR(30) NULL,
        `decided_by_name` VARCHAR(100) NULL, `channel_id` VARCHAR(30) NULL, `message_id` VARCHAR(30) NULL,
        `notified` TINYINT(1) NOT NULL DEFAULT 0, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `decided_at` TIMESTAMP NULL, INDEX `citizenid` (`citizenid`), INDEX `job_status` (`job`, `status`))]])
    db('query', [[CREATE TABLE IF NOT EXISTS `bp_application_logs` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, `action` VARCHAR(32) NOT NULL, `actor` VARCHAR(100) NULL,
        `data` LONGTEXT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)]])
    db('query', [[CREATE TABLE IF NOT EXISTS `bp_job_settings` (
        `job` VARCHAR(50) NOT NULL PRIMARY KEY, `roles` LONGTEXT NULL, `logs_channel` VARCHAR(30) NULL,
        `questions` LONGTEXT NULL, `promo_questions` LONGTEXT NULL, `updated_by` VARCHAR(100) NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)]])
    LoadSettings()
    LoadPeds()
end)

local function notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Job Center', description = msg, type = kind or 'inform', duration = 7000 })
end

local function strip(id, prefix)
    if not id then return nil end
    return (id:gsub('^' .. prefix .. ':', ''))
end

local function identifiers(src)
    local steamHex = strip(GetPlayerIdentifierByType(src, 'steam'), 'steam')
    local steam64
    if steamHex then
        local n = tonumber(steamHex, 16)
        if n then steam64 = string.format('%d', n) end
    end
    return {
        discord = strip(GetPlayerIdentifierByType(src, 'discord'), 'discord'),
        steam = steamHex and ('steam:' .. steamHex) or nil,
        steam64 = steam64,
        license = GetPlayerIdentifierByType(src, 'license'),
        name = GetPlayerName(src) or 'Unknown',
    }
end

local function saveIdentity(src, P)
    local id = identifiers(src)
    db('insert', [[INSERT INTO bp_identities (citizenid, license, discord, steam, fivem_name, char_name)
        VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE license = VALUES(license), discord = VALUES(discord),
        steam = VALUES(steam), fivem_name = VALUES(fivem_name), char_name = VALUES(char_name)]],
        { P.id, id.license, id.discord, id.steam, id.name, P.name })
    return id
end

local function isAdmin(src)
    return FW.IsAdmin(src)
end

local function canManage(src, job)
    if isAdmin(src) then return true end
    if Config.PedAccess ~= 'boss' then return false end
    local P = FW.Player(src)
    local j = P and P.job
    return j ~= nil and j.isboss == true and j.name == job
end

local function grade(job, level)
    local j = FW.Jobs()[job]
    if not j then return nil end
    return j.grades[tonumber(level) or -1]
end

local function gradeLevels(job)
    local out = {}
    local j = FW.Jobs()[job]
    if not j then return out end
    for n in pairs(j.grades) do out[#out + 1] = n end
    table.sort(out)
    return out
end

local function nextGrade(job, level)
    for _, n in ipairs(gradeLevels(job)) do
        if n > level then return n end
    end
    return nil
end

local function jobLabel(job) return (FW.Jobs()[job] or {}).label or job end
local function gradeName(job, level) return (grade(job, level) or {}).name or ('Grade ' .. tostring(level)) end

local function cut(s, n)
    s = tostring(s or '')
    if #s > n then return s:sub(1, n - 3) .. '...' end
    return s
end

local function clean(s)
    return (tostring(s):gsub('@', '@\u{200B}'):gsub('```', "'''"))
end

local function await(fn)
    local p, done = promise.new(), false
    local function finish(a, b) if not done then done = true p:resolve({ a, b }) end end
    local okCall, err = pcall(fn, finish)
    if not okCall then return nil, tostring(err) end
    SetTimeout(20000, function() finish(nil, 'timeout') end)
    local r = Citizen.Await(p)
    return r[1], r[2]
end

local function dsend(channel, payload)
    return await(function(cb) exports.bp_discord:send(tostring(channel), payload, cb) end)
end

local function dedit(channel, message, payload)
    return await(function(cb) exports.bp_discord:edit(tostring(channel), tostring(message), payload, cb) end)
end

local function reply(i, text)
    exports.bp_discord:followup(i.token, { content = text, flags = 64 }, function() end)
end

local function text(s) return { type = 10, content = s } end
local function sep() return { type = 14, divider = true, spacing = 1 } end

local function v2(color, parts)
    return { flags = 32768, allowed_mentions = { parse = {} }, components = { { type = 17, accent_color = color, components = parts } } }
end

local function realChannel(c) c = tostring(c or '') return c:match('^%d+$') and #c >= 17 and #c <= 20 and c ~= '000000000000000000' end

local function log(action, actor, data, line, job)
    MySQL.insert('INSERT INTO bp_application_logs (action, actor, data) VALUES (?, ?, ?)', { action, actor, json.encode(data or {}) })
    local targets = {}
    if realChannel(Config.LogsChannel) then targets[Config.LogsChannel] = true end
    local jl = job and Settings[job] and Settings[job].logs
    if realChannel(jl) then targets[jl] = true end
    local payload = v2(Config.Colors.log, { text(line .. '\n-# ' .. os.date('%Y-%m-%d %H:%M')) })
    for ch in pairs(targets) do CreateThread(function() dsend(ch, payload) end) end
end

local function buildMessage(app)
    local answers = json.decode(app.answers or '[]') or {}
    local isPromo = app.type == 'promotion'
    local title = isPromo and ('## %s Promotion Request · %s'):format(E.star, jobLabel(app.job))
        or ('## %s New Application · %s'):format(E.template, jobLabel(app.job))

    local steam = app.steam64 and ('[Profile](https://steamcommunity.com/profiles/%s) (`%s`)'):format(app.steam64, app.steam64) or '`not linked`'
    local who = table.concat({
        ('**Character:** %s (`%s`)'):format(clean(app.char_name), app.citizenid),
        ('**FiveM name:** %s'):format(clean(app.fivem_name)),
        ('**Discord:** %s'):format(app.discord and ('<@%s> (`%s`)'):format(app.discord, app.discord) or '`not linked`'),
        ('**Steam:** %s'):format(steam),
        ('**Phone:** %s'):format(app.phone or '-'),
        ('**Current job:** %s · %s'):format(jobLabel(app.current_job), gradeName(app.current_job, app.current_grade or 0)),
    }, '\n')
    if isPromo then
        who = who .. ('\n**Promotion:** %s %s %s'):format(gradeName(app.job, app.from_grade or 0), E.arrow, gradeName(app.job, app.target_grade))
    end

    local qa, budget = {}, 2600
    for _, a in ipairs(answers) do
        local body = cut(clean(a.a), 600):gsub('\n', '\n> ')
        local line = ('**%s**\n> %s'):format(cut(a.q, 120), body)
        if budget - #line < 0 then qa[#qa + 1] = '-# More answers saved in the database.' break end
        budget = budget - #line
        qa[#qa + 1] = line
    end

    local color = Config.Colors[app.status] or Config.Colors.pending
    local parts = { text(title), sep(), text(who), sep(), text(#qa > 0 and table.concat(qa, '\n\n') or '*No questions*'), sep() }

    if app.status == 'pending' then
        parts[#parts + 1] = text(('-# Application #%d · %s'):format(app.id, os.date('%Y-%m-%d %H:%M')))
        parts[#parts + 1] = { type = 1, components = {
            { type = 2, style = 3, label = isPromo and 'Promote' or 'Accept', custom_id = 'bpjobs:accept:' .. app.id, emoji = E.btnAccept },
            { type = 2, style = 4, label = 'Deny', custom_id = 'bpjobs:deny:' .. app.id, emoji = E.btnDeny },
        } }
    else
        local ok = app.status == 'accepted'
        local status = ('%s **%s** by %s'):format(ok and E.check or E.cross, ok and (isPromo and 'Promoted' or 'Accepted') or 'Denied',
            app.decided_by and ('<@%s>'):format(app.decided_by) or clean(app.decided_by_name or 'staff'))
        if app.reason and app.reason ~= '' then status = status .. '\n**Reason:** ' .. cut(clean(app.reason), 500) end
        parts[#parts + 1] = text(status .. ('\n-# Application #%d'):format(app.id))
    end
    return v2(color, parts)
end

local function pedList()
    local out = {}
    for _, p in pairs(Peds) do out[#out + 1] = p end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function LoadPeds()
    Peds = {}
    for _, r in ipairs(db('query', 'SELECT * FROM bp_application_peds') or {}) do
        r.enabled = r.enabled == 1 or r.enabled == true
        Peds[r.id] = r
    end
    TriggerClientEvent('bp_jobs:syncPeds', -1, pedList())
end

lib.callback.register('bp_jobs:getPeds', function() return pedList() end)

local function templateCopy(name)
    local t = Config.QuestionTemplates[name] or {}
    return json.decode(json.encode(t)) or {}
end

local function questionsFor(kind, job)
    local st = Settings[job] or {}
    local qs = kind == 'promotion' and st.promo or st.questions
    if type(qs) ~= 'table' or #qs == 0 then
        qs = templateCopy(kind == 'promotion' and Config.DefaultTemplates.promotion or Config.DefaultTemplates.hire)
    end
    local out = {}
    for i = 1, math.min(#qs, 10) do out[i] = qs[i] end
    return out
end

local function eligibility(src, pedId)
    local P = FW.Player(src)
    if not P then return false, 'Player not loaded.' end
    local ped = Peds[tonumber(pedId)]
    if not ped or not ped.enabled then return false, Config.Text.closed end
    if not FW.Jobs()[ped.job] then return false, 'This job no longer exists.' end

    local pc = GetEntityCoords(GetPlayerPed(src))
    if #(pc - vector3(ped.x, ped.y, ped.z)) > Config.MaxDistance then return false, 'You are too far away.' end

    local id = identifiers(src)
    if Config.RequireDiscord and not id.discord then return false, Config.Text.noDiscord end

    local cur = P.job
    local info = { job = ped.job, label = jobLabel(ped.job), kind = 'hire', target = Config.HireGrade, from = nil, ped = ped }

    if cur.name == ped.job then
        if not Config.Promotions.enabled then return false, 'You already work here.' end
        if cur.isboss and not Config.Promotions.bossesCanApply then return false, Config.Text.bossNoPromo end
        local level = cur.level
        local nxt = nextGrade(ped.job, level)
        if not nxt then return false, Config.Text.alreadyMax end
        info.kind, info.from, info.target = 'promotion', level, nxt
    elseif Config.Blacklist[cur.name] then
        return false, Config.Text.blacklisted:format(cur.label or cur.name)
    end

    local cid = P.id
    if db('scalar', "SELECT id FROM bp_applications WHERE citizenid = ? AND job = ? AND status = 'pending' LIMIT 1", { cid, ped.job }) then
        return false, Config.Text.pending
    end
    if Config.CooldownHours > 0 and db('scalar',
        "SELECT id FROM bp_applications WHERE citizenid = ? AND job = ? AND status = 'denied' AND decided_at > NOW() - INTERVAL ? HOUR LIMIT 1",
        { cid, ped.job, Config.CooldownHours }) then
        return false, Config.Text.cooldown
    end

    info.questions = questionsFor(info.kind, ped.job)
    return true, info, P, id
end

lib.callback.register('bp_jobs:check', function(src, pedId)
    local ok, info = eligibility(src, pedId)
    if not ok then return { ok = false, reason = info } end
    return {
        ok = true, kind = info.kind, label = info.label, questions = info.questions,
        targetName = gradeName(info.job, info.target),
    }
end)

local function validate(questions, input)
    local out = {}
    for i, q in ipairs(questions) do
        local v = input and input[i]
        local t = q.type or 'input'
        if t == 'number' then
            v = tonumber(v)
            if not v and q.required ~= false then return nil, ('"%s" needs a number.'):format(q.label) end
            if not v then v = '-'
            elseif (q.min and v < q.min) or (q.max and v > q.max) then
                return nil, ('"%s" must be between %s and %s.'):format(q.label, q.min or '-', q.max or '-')
            end
        elseif t == 'select' then
            local found = false
            for _, o in ipairs(q.options or {}) do if o == v then found = true end end
            if not found and q.required == false and (v == nil or v == '') then v, found = '-', true end
            if not found then return nil, ('Pick an answer for "%s".'):format(q.label) end
        else
            v = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
            if q.required ~= false and #v == 0 then return nil, ('"%s" is required.'):format(q.label) end
            if q.min and #v < q.min and (q.required ~= false or #v > 0) then return nil, ('"%s" needs at least %d characters.'):format(q.label, q.min) end
            if #v > (q.max or 600) then return nil, ('"%s" is too long (max %d).'):format(q.label, q.max or 600) end
        end
        out[#out + 1] = { q = q.label, a = tostring(v) }
    end
    return out
end

lib.callback.register('bp_jobs:submit', function(src, pedId, input)
    if busy[src] then return { ok = false, reason = 'Please wait...' } end
    busy[src] = true
    local result = (function()
        local ok, info, P = eligibility(src, pedId)
        if not ok then return { ok = false, reason = info } end
        local answers, err = validate(info.questions, input)
        if not answers then return { ok = false, reason = err } end

        local id = saveIdentity(src, P)
        local cur = P.job
        local app = {
            citizenid = P.id, job = info.job, type = info.kind, from_grade = info.from,
            target_grade = info.target, ped_id = info.ped.id, char_name = P.name, fivem_name = id.name,
            discord = id.discord, steam = id.steam, steam64 = id.steam64, license = id.license,
            phone = P.phone, current_job = cur.name, current_grade = cur.level,
            answers = json.encode(answers), status = 'pending', channel_id = info.ped.channel_id,
        }
        app.id = db('insert', [[INSERT INTO bp_applications (citizenid, job, type, from_grade, target_grade, ped_id,
            char_name, fivem_name, discord, steam, steam64, license, phone, current_job, current_grade, answers, status, channel_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            app.citizenid, app.job, app.type, app.from_grade, app.target_grade, app.ped_id, app.char_name, app.fivem_name,
            app.discord, app.steam, app.steam64, app.license, app.phone, app.current_job, app.current_grade, app.answers,
            app.status, app.channel_id })
        if not app.id then return { ok = false, reason = Config.Text.offline } end

        local msgId, derr = dsend(app.channel_id, buildMessage(app))
        if not msgId then
            db('query', 'DELETE FROM bp_applications WHERE id = ?', { app.id })
            print(('^1[bp_jobs] Could not post application to channel %s: %s^7'):format(app.channel_id, tostring(derr)))
            return { ok = false, reason = Config.Text.offline }
        end
        db('update', 'UPDATE bp_applications SET message_id = ? WHERE id = ?', { msgId, app.id })

        log('apply', app.citizenid, { id = app.id, job = app.job, type = app.type },
            ('%s **%s** applied for **%s** (%s) · #%d · <#%s>'):format(E.bell, clean(app.char_name), jobLabel(app.job),
                app.type == 'promotion' and ('promotion to ' .. gradeName(app.job, app.target_grade)) or 'hire', app.id, app.channel_id), app.job)
        return { ok = true }
    end)()
    busy[src] = nil
    return result
end)

local function discordCan(i, job)
    local roles = {}
    for _, r in ipairs(i.roles or {}) do roles[tostring(r)] = true end
    for _, key in ipairs({ '*', job }) do
        for _, r in ipairs((Settings[key] or {}).roles or {}) do if roles[tostring(r)] then return true end end
    end
    if not Config.BossesDecideOnDiscord or not i.userId or i.userId == '' then return false end

    for _, P in ipairs(FW.Players()) do
        if P.job.name == job and P.job.isboss and strip(GetPlayerIdentifierByType(P.source, 'discord'), 'discord') == i.userId then return true end
    end
    for _, r in ipairs(db('query', 'SELECT citizenid FROM bp_identities WHERE discord = ?', { i.userId }) or {}) do
        local j = FW.CurrentJob(r.citizenid)
        if j and j.name == job and j.isboss then return true end
    end
    return false
end

local function applyJob(app)
    if app.type == 'promotion' then
        local cur = FW.CurrentJob(app.citizenid)
        if not cur or cur.name ~= app.job then return false, 'They no longer work in this job.' end
    end
    if not grade(app.job, app.target_grade) then return false, 'That grade no longer exists.' end
    local ok, res = FW.SetJob(app.citizenid, app.job, app.target_grade)
    if not ok then return false, res or 'Character not found.' end
    return true, res
end

local function outcomeText(app)
    if app.status == 'accepted' then
        return app.type == 'promotion' and Config.Text.promoted:format(jobLabel(app.job), gradeName(app.job, app.target_grade))
            or Config.Text.accepted:format(jobLabel(app.job))
    end
    local t = Config.Text.denied:format(jobLabel(app.job))
    if app.reason and app.reason ~= '' then t = t .. ' Reason: ' .. app.reason end
    return t
end

local function tellApplicant(app, src)
    if src then
        notify(src, outcomeText(app), app.status == 'accepted' and 'success' or 'error')
        MySQL.update('UPDATE bp_applications SET notified = 1 WHERE id = ?', { app.id })
    end
    if Config.DMApplicant and app.discord then
        local ok = app.status == 'accepted'
        exports.bp_discord:dm(app.discord, v2(ok and Config.Colors.accepted or Config.Colors.denied, {
            text(('## %s %s'):format(ok and E.check or E.cross, ok and 'Application accepted' or 'Application denied')),
            text(clean(outcomeText(app))),
        }), function() end)
    end
end

local function decide(i, appId, accept, reason)
    local app = db('single', 'SELECT * FROM bp_applications WHERE id = ?', { appId })
    if not app then return reply(i, 'That application was not found.') end
    if app.status ~= 'pending' then return reply(i, 'This application was already handled.') end
    if not discordCan(i, app.job) then return reply(i, "You can't decide on " .. jobLabel(app.job) .. ' applications.') end
    if app.discord == i.userId then return reply(i, "You can't decide on your own application.") end

    local claimed = db('update',
        "UPDATE bp_applications SET status = ?, reason = ?, decided_by = ?, decided_by_name = ?, decided_at = NOW() WHERE id = ? AND status = 'pending'",
        { accept and 'accepted' or 'denied', reason, i.userId, i.userName, appId })
    if (claimed or 0) < 1 then return reply(i, 'This application was already handled.') end

    local onlineSrc
    if accept then
        local ok, res = applyJob(app)
        if not ok then
            db('update', "UPDATE bp_applications SET status = 'pending', reason = NULL, decided_by = NULL, decided_by_name = NULL, decided_at = NULL WHERE id = ?", { appId })
            return reply(i, 'Could not apply the job: ' .. res)
        end
        onlineSrc = res
    else
        onlineSrc = FW.SourceById(app.citizenid)
    end

    app.status, app.reason, app.decided_by, app.decided_by_name = accept and 'accepted' or 'denied', reason, i.userId, i.userName
    dedit(app.channel_id, app.message_id, buildMessage(app))
    tellApplicant(app, onlineSrc)

    local what = accept and (app.type == 'promotion' and ('promoted to ' .. gradeName(app.job, app.target_grade)) or 'accepted') or 'denied'
    log(accept and 'accept' or 'deny', i.userId, { id = app.id, job = app.job, reason = reason, offline = onlineSrc == nil },
        ('%s <@%s> **%s** %s for **%s** · #%d%s%s'):format(accept and E.check or E.cross, i.userId, what, clean(app.char_name),
            jobLabel(app.job), app.id, onlineSrc and '' or ' · *offline*', reason and reason ~= '' and ('\n> ' .. cut(clean(reason), 300)) or ''), app.job)
    reply(i, ('Done: %s %s.'):format(app.char_name, what))
end

AddEventHandler('bp_discord:interaction', function(i)
    local action, id = (i.customId or ''):match('^bpjobs:(%a+):(%d+)')
    if not action then return end
    id = tonumber(id)
    if i.kind == 'button' and action == 'accept' then
        decide(i, id, true, nil)
    elseif i.kind == 'modal' and action == 'deny' then
        local reason = i.fields and i.fields.reason or ''
        decide(i, id, false, reason ~= '' and cut(reason, 500) or nil)
    end
end)

local function registerModals()
    exports.bp_discord:claim('bpjobs:')
    exports.bp_discord:registerModal('bpjobs:deny:', {
        title = 'Deny application',
        inputs = { { id = 'reason', label = 'Reason (sent to the applicant)', style = 'paragraph', required = false, max = 500,
            placeholder = 'Optional' } },
    })
end

CreateThread(function()
    while GetResourceState('bp_discord') ~= 'started' do Wait(500) end
    registerModals()
end)
AddEventHandler('onResourceStart', function(res) if res == 'bp_discord' then Wait(500) registerModals() end end)

FW.OnLoaded(function(src)
    Wait(1000)
    local P = FW.Player(src)
    if not P then return end
    saveIdentity(src, P)
    local rows = db('query', "SELECT * FROM bp_applications WHERE citizenid = ? AND status <> 'pending' AND notified = 0", { P.id }) or {}
    if #rows == 0 then return end
    SetTimeout(8000, function()
        for _, app in ipairs(rows) do notify(src, outcomeText(app), app.status == 'accepted' and 'success' or 'error') end
        MySQL.update("UPDATE bp_applications SET notified = 1 WHERE citizenid = ? AND status <> 'pending'", { P.id })
    end)
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)

local function validChannel(c) c = tostring(c or '') return c:match('^%d+$') and #c >= 17 and #c <= 20 end

lib.callback.register('bp_jobs:menu', function(src)
    local admin = isAdmin(src)
    local P = FW.Player(src)
    local j = P and P.job
    local bossJob = (Config.PedAccess == 'boss' and j and j.isboss) and j.name or nil
    if not admin and not bossJob then return { ok = false } end

    local jobs = {}
    if admin then
        for name, data in pairs(FW.Jobs()) do
            if name ~= 'unemployed' then jobs[#jobs + 1] = { value = name, label = ('%s (%s)'):format(data.label or name, name) } end
        end
        table.sort(jobs, function(a, b) return a.label < b.label end)
    else
        jobs[1] = { value = bossJob, label = jobLabel(bossJob) }
    end

    local peds = {}
    for _, p in ipairs(pedList()) do
        if admin or p.job == bossJob then
            p.jobLabel = jobLabel(p.job)
            peds[#peds + 1] = p
        end
    end
    return { ok = true, admin = admin, jobs = jobs, peds = peds, scenarios = Config.Scenarios, defaultModel = Config.DefaultPedModel }
end)

local function actorName(src)
    local P = FW.Player(src)
    return P and ('%s (%s)'):format(P.name, GetPlayerName(src)) or GetPlayerName(src) or 'console'
end

local function readPedInput(src, d)
    if type(d) ~= 'table' then return nil, 'Invalid data.' end
    if not FW.Jobs()[d.job] then return nil, 'Unknown job.' end
    if not canManage(src, d.job) then return nil, Config.Text.noAccess end
    if not validChannel(d.channel) then return nil, 'Channel ID must be 17-20 digits (right-click channel > Copy Channel ID).' end
    local label = tostring(d.label or ''):gsub('^%s+', ''):gsub('%s+$', '')
    label = cut(label, 60)
    if label == '' then label = jobLabel(d.job) end
    local model = tostring(d.model or ''):match('^[%w_]+$') or Config.DefaultPedModel
    local scen = 'none'
    for _, s in ipairs(Config.Scenarios) do if s.value == d.scenario then scen = s.value end end
    return { job = d.job, label = label, model = model, channel = tostring(d.channel), scenario = scen }
end

lib.callback.register('bp_jobs:addPed', function(src, d)
    local v, err = readPedInput(src, d)
    if not v then return { ok = false, reason = err } end
    local ped = GetPlayerPed(src)
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local id = db('insert', 'INSERT INTO bp_application_peds (job, label, model, scenario, x, y, z, h, channel_id, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { v.job, v.label, v.model, v.scenario, c.x, c.y, c.z, h, v.channel, (FW.Player(src) or {}).id })
    LoadPeds()
    log('ped_add', actorName(src), { id = id, job = v.job, channel = v.channel },
        ('%s **%s** placed interview ped #%d for **%s** · <#%s>'):format(E.staff, clean(actorName(src)), id, jobLabel(v.job), v.channel), v.job)
    return { ok = true, id = id }
end)

lib.callback.register('bp_jobs:editPed', function(src, id, d)
    local p = Peds[tonumber(id)]
    if not p or not canManage(src, p.job) then return { ok = false, reason = Config.Text.noAccess } end
    if not isAdmin(src) then d.job = p.job end
    local v, err = readPedInput(src, d)
    if not v then return { ok = false, reason = err } end
    db('update', 'UPDATE bp_application_peds SET job = ?, label = ?, model = ?, scenario = ?, channel_id = ? WHERE id = ?',
        { v.job, v.label, v.model, v.scenario, v.channel, p.id })
    LoadPeds()
    log('ped_edit', actorName(src), { id = p.id, data = v }, ('%s **%s** edited interview ped #%d (%s) · <#%s>'):format(E.staff, clean(actorName(src)), p.id, jobLabel(v.job), v.channel), v.job)
    return { ok = true }
end)

lib.callback.register('bp_jobs:pedAction', function(src, id, action)
    local p = Peds[tonumber(id)]
    if not p or not canManage(src, p.job) then return { ok = false, reason = Config.Text.noAccess } end
    local ped = GetPlayerPed(src)

    if action == 'move' then
        local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
        db('update', 'UPDATE bp_application_peds SET x = ?, y = ?, z = ?, h = ? WHERE id = ?', { c.x, c.y, c.z, h, p.id })
    elseif action == 'toggle' then
        db('update', 'UPDATE bp_application_peds SET enabled = ? WHERE id = ?', { p.enabled and 0 or 1, p.id })
    elseif action == 'delete' then
        db('query', 'DELETE FROM bp_application_peds WHERE id = ?', { p.id })
    elseif action == 'teleport' then
        if not isAdmin(src) then return { ok = false, reason = Config.Text.noAccess } end
        SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
        return { ok = true }
    elseif action == 'test' then
        local msg, err = dsend(p.channel_id, v2(Config.Colors.pending, {
            text(('%s **Test message** from interview ped #%d (%s). Applications will show up here.'):format(E.bell, p.id, jobLabel(p.job))) }))
        if not msg then return { ok = false, reason = 'Discord error: ' .. cut(err, 150) } end
        return { ok = true }
    else
        return { ok = false, reason = 'Unknown action.' }
    end

    LoadPeds()
    log('ped_' .. action, actorName(src), { id = p.id },
        ('%s **%s** %s interview ped #%d (%s)'):format(E.staff, clean(actorName(src)),
            action == 'move' and 'moved' or action == 'delete' and 'deleted' or (p.enabled and 'closed' or 'opened'), p.id, jobLabel(p.job)), p.job)
    return { ok = true }
end)

local function decode(v)
    if not v or v == '' then return nil end
    local ok, t = pcall(json.decode, v)
    return ok and type(t) == 'table' and t or nil
end

function LoadSettings()
    Settings = {}
    for _, r in ipairs(db('query', 'SELECT * FROM bp_job_settings') or {}) do
        Settings[r.job] = { roles = decode(r.roles) or {}, logs = r.logs_channel, questions = decode(r.questions), promo = decode(r.promo_questions) }
    end
end

local function saveSettings(job, actor)
    local st = Settings[job]
    db('insert', [[INSERT INTO bp_job_settings (job, roles, logs_channel, questions, promo_questions, updated_by) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE roles = VALUES(roles), logs_channel = VALUES(logs_channel), questions = VALUES(questions),
        promo_questions = VALUES(promo_questions), updated_by = VALUES(updated_by)]],
        { job, json.encode(st.roles or {}), st.logs, st.questions and json.encode(st.questions) or nil,
          st.promo and json.encode(st.promo) or nil, actor })
end

local function settingsFor(job)
    Settings[job] = Settings[job] or { roles = {} }
    return Settings[job]
end

local function canSettings(src, job)
    if job == '*' then return isAdmin(src) end
    return FW.Jobs()[job] ~= nil and canManage(src, job)
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
local TYPES = { input = true, textarea = true, number = true, select = true }

local function cleanQuestions(list)
    if type(list) ~= 'table' then return nil, 'Invalid questions.' end
    local out = {}
    for i, q in ipairs(list) do
        if i > Config.MaxQuestions then return nil, ('Max %d questions.'):format(Config.MaxQuestions) end
        if type(q) ~= 'table' then return nil, 'Invalid question.' end
        local label = cut(trim(q.label), 120)
        if label == '' then return nil, ('Question %d has no text.'):format(i) end
        local t = TYPES[q.type] and q.type or 'input'
        local nq = { label = label, type = t, required = q.required ~= false }
        local mn, mx = tonumber(q.min), tonumber(q.max)
        if t == 'number' then
            nq.min, nq.max = mn, mx
        elseif t == 'select' then
            nq.options = {}
            for _, o in ipairs(type(q.options) == 'table' and q.options or {}) do
                local v = cut(trim(o), 80)
                if v ~= '' and #nq.options < 25 then nq.options[#nq.options + 1] = v end
            end
            if #nq.options < 2 then return nil, ('"%s" needs at least 2 options.'):format(label) end
        else
            nq.min = mn and math.max(0, math.min(math.floor(mn), 1000)) or nil
            nq.max = math.max(1, math.min(math.floor(mx or 600), 1000))
        end
        if nq.min and nq.max and nq.min > nq.max then return nil, ('"%s": min is bigger than max.'):format(label) end
        out[#out + 1] = nq
    end
    return out
end

local function parseRoles(str)
    local roles, seen = {}, {}
    for id in tostring(str or ''):gmatch('%d+') do
        if #id >= 17 and #id <= 20 and not seen[id] and #roles < 25 then seen[id] = true roles[#roles + 1] = id end
    end
    return roles
end

local function templateNames()
    local out = {}
    for name, qs in pairs(Config.QuestionTemplates) do out[#out + 1] = { name = name, count = #qs } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

lib.callback.register('bp_jobs:getSettings', function(src, job)
    if not canSettings(src, job) then return { ok = false, reason = Config.Text.noAccess } end
    local st = Settings[job] or {}
    return {
        ok = true, job = job, label = job == '*' and 'All jobs' or jobLabel(job),
        roles = st.roles or {}, logs = st.logs,
        questions = st.questions or {}, promo = st.promo or {},
        defaults = { hire = Config.DefaultTemplates.hire, promotion = Config.DefaultTemplates.promotion },
        templates = templateNames(),
    }
end)

lib.callback.register('bp_jobs:saveSetting', function(src, job, field, value)
    if not canSettings(src, job) then return { ok = false, reason = Config.Text.noAccess } end
    local st, actor = settingsFor(job), actorName(src)
    local line
    if field == 'roles' then
        st.roles = parseRoles(value)
        local list = {}
        for _, r in ipairs(st.roles) do list[#list + 1] = '<@&' .. r .. '>' end
        line = ('%s **%s** set decision roles for **%s**: %s'):format(E.staff, clean(actor), job == '*' and 'all jobs' or jobLabel(job),
            #list > 0 and table.concat(list, ' ') or '*none*')
    elseif field == 'logs' and job ~= '*' then
        local c = trim(value)
        if c ~= '' and not realChannel(c) then return { ok = false, reason = 'Channel ID must be 17-20 digits.' } end
        st.logs = c ~= '' and c or nil
        line = ('%s **%s** set the logs channel for **%s**: %s'):format(E.staff, clean(actor), jobLabel(job), st.logs and ('<#' .. st.logs .. '>') or '*none*')
    elseif (field == 'questions' or field == 'promo') and job ~= '*' then
        local qs, err = cleanQuestions(value)
        if not qs then return { ok = false, reason = err } end
        st[field] = #qs > 0 and qs or nil
        line = ('%s **%s** updated the %s questions for **%s** (%d)'):format(E.staff, clean(actor),
            field == 'promo' and 'promotion' or 'application', jobLabel(job), #qs)
    else
        return { ok = false, reason = 'Unknown setting.' }
    end
    saveSettings(job, actor)
    log('settings', actor, { job = job, field = field }, line, job ~= '*' and job or nil)
    return { ok = true, value = st[field] }
end)

lib.callback.register('bp_jobs:template', function(src, name)
    if not Config.QuestionTemplates[name] then return nil end
    return templateCopy(name)
end)
