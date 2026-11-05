FW = {}

local fw = Config.Framework
if fw == 'auto' then
    if GetResourceState('qbx_core') ~= 'missing' then fw = 'qbox'
    elseif GetResourceState('qb-core') ~= 'missing' then fw = 'qbcore'
    elseif GetResourceState('es_extended') ~= 'missing' then fw = 'esx'
    else fw = 'standalone' end
end
FW.name = fw

local QB, ESX
if fw == 'qbcore' then QB = exports['qb-core']:GetCoreObject()
elseif fw == 'esx' then ESX = exports.es_extended:getSharedObject() end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

local SA = {}

local cache, cacheAt = nil, -60000
local function rawJobs()
    if fw == 'qbcore' then return QB.Shared.Jobs end
    if fw == 'qbox' then return exports.qbx_core:GetJobs() end
    if fw == 'esx' then return (ESX.GetJobs and ESX.GetJobs()) or ESX.Jobs end
    return Config.Standalone.Jobs
end

function FW.Jobs()
    if cache and GetGameTimer() - cacheAt < 30000 then return cache end
    local out = {}
    for name, j in pairs(rawJobs() or {}) do
        local grades = {}
        for k, g in pairs(j.grades or {}) do
            local lvl = tonumber(k) or tonumber(g.grade)
            if lvl then
                grades[lvl] = {
                    name = (fw == 'esx' and g.label) or g.name or ('Grade ' .. lvl),
                    isboss = g.isboss == true or (fw == 'esx' and g.name == 'boss'),
                    payment = g.payment or g.salary or 0,
                }
            end
        end
        out[name] = { label = j.label or name, grades = grades, type = j.type, defaultDuty = j.defaultDuty }
    end
    cache, cacheAt = out, GetGameTimer()
    return out
end

local function gradeOf(job, level)
    local j = FW.Jobs()[job]
    return j and j.grades[tonumber(level) or -1] or nil
end

local function qbNorm(P)
    if not P then return nil end
    local d = P.PlayerData
    local c, j = d.charinfo or {}, d.job or {}
    return {
        source = d.source, id = d.citizenid, phone = c.phone,
        name = trim((c.firstname or '') .. ' ' .. (c.lastname or '')),
        job = { name = j.name, label = j.label, level = tonumber(j.grade and j.grade.level) or 0, isboss = j.isboss == true },
    }
end

function FW.Player(src)
    src = tonumber(src)
    if not src then return nil end
    if fw == 'qbcore' then return qbNorm(QB.Functions.GetPlayer(src)) end
    if fw == 'qbox' then return qbNorm(exports.qbx_core:GetPlayer(src)) end
    if fw == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if not x then return nil end
        local j = x.getJob and x.getJob() or x.job or {}
        return {
            source = src, id = x.identifier, name = trim(x.getName and x.getName() or GetPlayerName(src)),
            phone = x.get and (x.get('phoneNumber') or x.get('phone_number')) or nil,
            job = { name = j.name, label = j.label, level = tonumber(j.grade) or 0, isboss = j.grade_name == 'boss' },
        }
    end
    local s = SA[src]
    if not s then return nil end
    local g = gradeOf(s.job, s.grade) or {}
    return {
        source = src, id = s.id, name = GetPlayerName(src) or 'Unknown', phone = nil,
        job = { name = s.job, label = (FW.Jobs()[s.job] or {}).label or s.job, level = s.grade, isboss = g.isboss == true },
    }
end

function FW.Players()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local P = FW.Player(tonumber(s))
        if P then out[#out + 1] = P end
    end
    return out
end

function FW.SourceById(id)
    if not id then return nil end
    if fw == 'qbcore' then local P = QB.Functions.GetPlayerByCitizenId(id) return P and P.PlayerData.source end
    if fw == 'qbox' then local P = exports.qbx_core:GetPlayerByCitizenId(id) return P and P.PlayerData.source end
    if fw == 'esx' then local x = ESX.GetPlayerFromIdentifier(id) return x and x.source end
    for src, s in pairs(SA) do if s.id == id then return src end end
end

function FW.OfflineJob(id)
    if fw == 'qbcore' or fw == 'qbox' then
        local row = MySQL.single.await('SELECT job FROM players WHERE citizenid = ?', { id })
        local j = row and json.decode(row.job or '{}') or nil
        return j and { name = j.name, level = tonumber(j.grade and j.grade.level) or 0, isboss = j.isboss == true } or nil
    end
    if fw == 'esx' then
        local row = MySQL.single.await('SELECT job, job_grade FROM users WHERE identifier = ?', { id })
        if not row then return nil end
        local g = gradeOf(row.job, row.job_grade) or {}
        return { name = row.job, level = tonumber(row.job_grade) or 0, isboss = g.isboss == true }
    end
    local row = MySQL.single.await('SELECT job, grade FROM bp_standalone_jobs WHERE identifier = ?', { id })
    if not row then return nil end
    local g = gradeOf(row.job, row.grade) or {}
    return { name = row.job, level = tonumber(row.grade) or 0, isboss = g.isboss == true }
end

function FW.CurrentJob(id)
    local src = FW.SourceById(id)
    if src then local P = FW.Player(src) return P and P.job, src end
    return FW.OfflineJob(id), nil
end

local function standaloneSet(id, job, level)
    MySQL.insert.await('INSERT INTO bp_standalone_jobs (identifier, job, grade) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE job = VALUES(job), grade = VALUES(grade)',
        { id, job, level })
    local src = FW.SourceById(id)
    if src then
        SA[src].job, SA[src].grade = job, level
        TriggerEvent('bp_jobs:jobChanged', src, job, level)
        TriggerClientEvent('bp_jobs:jobChanged', src, job, level)
    end
    return true, src
end

function FW.SetJob(id, job, level)
    local j, g = FW.Jobs()[job], gradeOf(job, level)
    if not j or not g then return false, 'That job or grade does not exist.' end
    local src = FW.SourceById(id)

    if fw == 'qbcore' then
        if src then QB.Functions.GetPlayer(src).Functions.SetJob(job, level) return true, src end
        local enc = json.encode({ name = job, label = j.label, payment = g.payment, type = j.type, onduty = j.defaultDuty == true,
            isboss = g.isboss, grade = { name = g.name, level = level } })
        local n = MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', { enc, id })
        if (n or 0) < 1 then return false, 'Character not found.' end
        return true, nil
    end
    if fw == 'qbox' then
        local ok, err = pcall(function()
            exports.qbx_core:AddPlayerToJob(id, job, level)
            exports.qbx_core:SetPlayerPrimaryJob(id, job)
        end)
        if not ok then return false, tostring(err) end
        return true, src
    end
    if fw == 'esx' then
        if src then ESX.GetPlayerFromId(src).setJob(job, level) return true, src end
        local n = MySQL.update.await('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { job, level, id })
        if (n or 0) < 1 then return false, 'Character not found.' end
        return true, nil
    end
    return standaloneSet(id, job, level)
end

function FW.IsAdmin(src)
    if src == 0 or IsPlayerAceAllowed(src, 'bp_jobs.admin') then return true end
    for _, perm in ipairs(Config.AdminPermissions) do
        if fw == 'qbcore' and QB.Functions.HasPermission(src, perm) then return true end
        if fw == 'qbox' then
            local ok, has = pcall(function() return exports.qbx_core:HasPermission(src, perm) end)
            if (ok and has) or IsPlayerAceAllowed(src, perm) then return true end
        end
        if fw == 'esx' then
            local x = ESX.GetPlayerFromId(src)
            if x and x.getGroup and x.getGroup() == perm then return true end
        end
    end
    return false
end

local loadedHandlers = {}
function FW.OnLoaded(cb) loadedHandlers[#loadedHandlers + 1] = cb end
local function fireLoaded(src)
    for _, cb in ipairs(loadedHandlers) do CreateThread(function() cb(src) end) end
end

if fw == 'qbcore' or fw == 'qbox' then
    AddEventHandler('QBCore:Server:PlayerLoaded', function(P) fireLoaded(P.PlayerData.source) end)
elseif fw == 'esx' then
    AddEventHandler('esx:playerLoaded', function(src) fireLoaded(src) end)
else
    local function loadSA(src)
        local id = GetPlayerIdentifierByType(src, 'license')
        if not id then return end
        local row = MySQL.single.await('SELECT job, grade FROM bp_standalone_jobs WHERE identifier = ?', { id })
        SA[src] = { id = id, job = row and row.job or Config.Standalone.DefaultJob, grade = row and tonumber(row.grade) or 0 }
        fireLoaded(src)
    end
    CreateThread(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bp_standalone_jobs` (`identifier` VARCHAR(60) NOT NULL PRIMARY KEY,
            `job` VARCHAR(50) NOT NULL, `grade` INT NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)]])
        for _, s in ipairs(GetPlayers()) do loadSA(tonumber(s)) end
    end)
    AddEventHandler('playerJoining', function() local src = source CreateThread(function() loadSA(src) end) end)
    AddEventHandler('playerDropped', function() SA[source] = nil end)

    exports('GetJob', function(src) local P = FW.Player(src) return P and P.job end)
    exports('SetJob', function(src, job, level)
        local s = SA[tonumber(src)]
        if not s then return false end
        return (FW.SetJob(s.id, job, tonumber(level) or 0))
    end)
end

print(('^5[bp_jobs]^7 Framework: ^2%s^7'):format(fw))
