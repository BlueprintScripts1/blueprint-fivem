local Peds = {}
local spawned = {}
local points = {}
local blips = {}
local open = false

local function notify(msg, kind)
    lib.notify({ title = 'Job Center', description = msg, type = kind or 'inform', duration = 6000 })
end

local function buildRows(questions, defaults)
    local rows = {}
    for i, q in ipairs(questions) do
        local t = q.type or 'input'
        local row = { label = q.label, description = q.description, required = q.required ~= false, default = defaults and defaults[i] }
        if t == 'number' then
            row.type, row.min, row.max = 'number', q.min, q.max
        elseif t == 'select' then
            row.type, row.options = 'select', {}
            for _, o in ipairs(q.options or {}) do row.options[#row.options + 1] = { value = o, label = o } end
        elseif t == 'textarea' then
            row.type, row.autosize = 'textarea', true
            row.placeholder = q.min and ('At least %d characters'):format(q.min) or nil
        else
            row.type, row.placeholder = 'input', q.placeholder
        end
        rows[i] = row
    end
    return rows
end

local function localCheck(questions, input)
    for i, q in ipairs(questions) do
        local v = input[i]
        if (q.type or 'input') == 'input' or q.type == 'textarea' then
            local len = #tostring(v or '')
            if q.min and len < q.min then return ('"%s" needs at least %d characters (you wrote %d).'):format(q.label, q.min, len) end
            if len > (q.max or 600) then return ('"%s" is too long (max %d).'):format(q.label, q.max or 600) end
        end
    end
end

local function apply(pedId)
    if open then return end
    open = true
    local info = lib.callback.await('bp_jobs:check', false, pedId)
    if not info or not info.ok then
        open = false
        return notify(info and info.reason or 'Try again later.', 'error')
    end

    local title = info.kind == 'promotion' and ('Promotion: %s'):format(info.targetName) or ('Apply: %s'):format(info.label)
    local input
    while true do
        input = lib.inputDialog(title, buildRows(info.questions, input), { allowCancel = true, size = 'md' })
        if not input then open = false return end
        local err = localCheck(info.questions, input)
        if not err then break end
        notify(err, 'error')
    end

    local confirm = lib.alertDialog({
        header = 'Send application?',
        content = ('Your application for **%s** will be sent to the staff on Discord.'):format(info.label),
        centered = true, cancel = true, labels = { confirm = 'Send' },
    })
    if confirm ~= 'confirm' then open = false return end

    local res = lib.callback.await('bp_jobs:submit', false, pedId, input)
    open = false
    if res and res.ok then notify(Config.Text.sent, 'success') else notify(res and res.reason or Config.Text.offline, 'error') end
end

local function despawn(id)
    local e = spawned[id]
    if e then
        if Config.Interaction == 'ox_target' then pcall(function() exports.ox_target:removeLocalEntity(e) end)
        elseif Config.Interaction == 'qb-target' then pcall(function() exports['qb-target']:RemoveTargetEntity(e) end) end
        if DoesEntityExist(e) then DeleteEntity(e) end
        spawned[id] = nil
    end
end

local function spawn(d)
    if spawned[d.id] then return end
    local model = joaat(d.model)
    if not IsModelInCdimage(model) or not IsModelAPed(model) then model = joaat(Config.DefaultPedModel) end
    if not pcall(lib.requestModel, model, 10000) then return end
    if spawned[d.id] or not Peds[d.id] then return end

    local ped = CreatePed(4, model, d.x, d.y, d.z - 1.0, d.h, false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    if d.scenario and d.scenario ~= 'none' then TaskStartScenarioInPlace(ped, d.scenario, 0, true) end
    spawned[d.id] = ped

    local label = Config.Text.target:format(d.label)
    if Config.Interaction == 'ox_target' then
        exports.ox_target:addLocalEntity(ped, { {
            name = 'bp_jobs_apply_' .. d.id, icon = 'fa-solid fa-file-signature', label = label, distance = 2.5,
            onSelect = function() apply(d.id) end,
        } })
    elseif Config.Interaction == 'qb-target' then
        exports['qb-target']:AddTargetEntity(ped, {
            options = { { icon = 'fas fa-file-signature', label = label, action = function() apply(d.id) end } },
            distance = 2.5,
        })
    end
end

local function clearAll()
    for id, pt in pairs(points) do pt:remove() points[id] = nil end
    for id in pairs(spawned) do despawn(id) end
    for id, b in pairs(blips) do RemoveBlip(b) blips[id] = nil end
    lib.hideTextUI()
end

local function setPeds(list)
    clearAll()
    Peds = {}
    for _, d in ipairs(list or {}) do
        if d.enabled then
            Peds[d.id] = d
            local pt = lib.points.new({ coords = vec3(d.x, d.y, d.z), distance = Config.SpawnDistance })
            function pt:onEnter() spawn(d) end
            function pt:onExit() despawn(d.id) end
            if Config.Interaction == 'textui' then
                local shown = false
                function pt:nearby()
                    local near = self.currentDistance < 2.0
                    if near and not shown then lib.showTextUI(Config.Text.textui:format(d.label)) shown = true
                    elseif not near and shown then lib.hideTextUI() shown = false end
                    if near and IsControlJustReleased(0, 38) then apply(d.id) end
                end
            end
            points[d.id] = pt

            if Config.Blip.enabled then
                local b = AddBlipForCoord(d.x, d.y, d.z)
                SetBlipSprite(b, Config.Blip.sprite)
                SetBlipColour(b, Config.Blip.color)
                SetBlipScale(b, Config.Blip.scale)
                SetBlipAsShortRange(b, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName('Job Interview: ' .. d.label)
                EndTextCommandSetBlipName(b)
                blips[d.id] = b
            end
        end
    end
end

RegisterNetEvent('bp_jobs:syncPeds', setPeds)

local function load() setPeds(lib.callback.await('bp_jobs:getPeds', false)) end
for _, ev in ipairs({ 'QBCore:Client:OnPlayerLoaded', 'esx:playerLoaded', 'playerSpawned' }) do
    RegisterNetEvent(ev, function() CreateThread(load) end)
end
AddEventHandler('onClientResourceStart', function(res) if res == GetCurrentResourceName() then CreateThread(load) end end)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then clearAll() end end)

local openManager

local function pedDialog(data, current)
    local scen = {}
    for _, s in ipairs(data.scenarios) do scen[#scen + 1] = { value = s.value, label = s.label } end
    local input = lib.inputDialog(current and ('Edit ped #%d'):format(current.id) or 'New interview ped', {
        { type = 'select', label = 'Job', options = data.jobs, required = true, default = current and current.job or data.jobs[1].value, disabled = not data.admin },
        { type = 'input', label = 'Desk name', description = 'Shown on the target and blip', required = true, max = 60, default = current and current.label },
        { type = 'input', label = 'Ped model', description = 'e.g. a_m_y_business_03, s_f_y_cop_01', required = true, default = current and current.model or data.defaultModel },
        { type = 'input', label = 'Discord channel ID', description = 'Applications for this ped are posted here', required = true, default = current and current.channel_id },
        { type = 'select', label = 'Animation', options = scen, default = current and current.scenario or scen[1].value },
    }, { allowCancel = true })
    if not input then return end

    local model = tostring(input[3] or ''):gsub('%s', '')
    if not IsModelInCdimage(joaat(model)) or not IsModelAPed(joaat(model)) then
        return notify(('"%s" is not a valid ped model.'):format(model), 'error')
    end
    return { job = data.admin and input[1] or (current and current.job or data.jobs[1].value), label = input[2], model = model,
        channel = tostring(input[4] or ''):gsub('%s', ''), scenario = input[5] }
end

local function pedMenu(data, p)
    local function act(action, okMsg)
        local r = lib.callback.await('bp_jobs:pedAction', false, p.id, action)
        if r and r.ok then notify(okMsg, 'success') else notify(r and r.reason or 'Failed.', 'error') end
        openManager()
    end
    local options = {
        { title = 'Edit', description = 'Job, name, model, channel, animation', icon = 'pen',
          onSelect = function()
              local d = pedDialog(data, p)
              if not d then return openManager() end
              local r = lib.callback.await('bp_jobs:editPed', false, p.id, d)
              if r and r.ok then notify('Ped updated.', 'success') else notify(r and r.reason or 'Failed.', 'error') end
              openManager()
          end },
        { title = 'Move to my position', icon = 'location-crosshairs', onSelect = function() act('move', 'Ped moved.') end },
        { title = 'Send test message', description = 'Checks the bot can post in <#' .. p.channel_id .. '>', icon = 'paper-plane',
          onSelect = function() act('test', 'Test message sent. Check the channel.') end },
        { title = p.enabled and 'Close applications' or 'Open applications', icon = p.enabled and 'lock' or 'lock-open',
          onSelect = function() act('toggle', p.enabled and 'Desk closed.' or 'Desk opened.') end },
    }
    if data.admin then
        options[#options + 1] = { title = 'Teleport', icon = 'person-walking-arrow-right', onSelect = function() act('teleport', 'Teleported.') end }
    end
    options[#options + 1] = { title = 'Delete', icon = 'trash', iconColor = '#ef4444', onSelect = function()
        local c = lib.alertDialog({ header = 'Delete ped?', content = ('Delete **%s** (#%d)? Saved applications stay in the database.'):format(p.label, p.id), centered = true, cancel = true })
        if c == 'confirm' then act('delete', 'Ped deleted.') else openManager() end
    end }

    lib.registerContext({ id = 'bp_jobs_ped', title = ('#%d · %s'):format(p.id, p.label), menu = 'bp_jobs_manager', options = options })
    lib.showContext('bp_jobs_ped')
end

openManager = function()
    local data = lib.callback.await('bp_jobs:menu', false)
    if not data or not data.ok then return notify(Config.Text.noAccess, 'error') end

    local options = { {
        title = 'Add interview ped here', description = 'Places a ped where you are standing, facing your direction', icon = 'plus',
        onSelect = function()
            local d = pedDialog(data)
            if not d then return openManager() end
            local r = lib.callback.await('bp_jobs:addPed', false, d)
            if r and r.ok then notify(('Ped #%d placed.'):format(r.id), 'success') else notify(r and r.reason or 'Failed.', 'error') end
            openManager()
        end,
    } }
    for _, p in ipairs(data.peds) do
        options[#options + 1] = {
            title = ('#%d · %s'):format(p.id, p.label),
            description = ('%s · channel %s%s'):format(p.jobLabel, p.channel_id, p.enabled and '' or ' · CLOSED'),
            icon = p.enabled and 'user-tie' or 'user-slash', arrow = true,
            onSelect = function() pedMenu(data, p) end,
        }
    end
    lib.registerContext({ id = 'bp_jobs_manager', title = 'Interview Peds', menu = 'bp_jobs_main', options = options })
    lib.showContext('bp_jobs_manager')
end

local openSettings, openQuestions
local TYPE_OPTIONS = {
    { value = 'input', label = 'Short text' }, { value = 'textarea', label = 'Long text' },
    { value = 'number', label = 'Number' }, { value = 'select', label = 'Pick from a list' },
}
local TYPE_NAME = { input = 'Short text', textarea = 'Long text', number = 'Number', select = 'List' }

local function save(job, field, value, okMsg)
    local r = lib.callback.await('bp_jobs:saveSetting', false, job, field, value)
    if r and r.ok then notify(okMsg, 'success') else notify(r and r.reason or 'Failed.', 'error') end
    return r and r.ok
end

local function describe(q)
    local bits = { TYPE_NAME[q.type] or 'Short text', q.required == false and 'optional' or 'required' }
    if q.type == 'select' then bits[#bits + 1] = table.concat(q.options or {}, ' / ')
    elseif q.min or q.max then bits[#bits + 1] = ('%s-%s%s'):format(q.min or 0, q.max or '∞', q.type == 'number' and '' or ' chars') end
    return table.concat(bits, ' · ')
end

local function questionDialog(q)
    local input = lib.inputDialog(q and 'Edit question' or 'New question', {
        { type = 'input', label = 'Question', required = true, max = 120, default = q and q.label },
        { type = 'select', label = 'Answer type', options = TYPE_OPTIONS, required = true, default = q and q.type or 'textarea' },
        { type = 'checkbox', label = 'Required', checked = not q or q.required ~= false },
        { type = 'number', label = 'Min', description = 'Text: minimum characters · Number: lowest value · empty = none', default = q and q.min },
        { type = 'number', label = 'Max', description = 'Text: maximum characters (default 600) · Number: highest value', default = q and q.max },
        { type = 'textarea', label = 'Options (only for "Pick from a list")', description = 'One option per line', autosize = true,
          default = q and q.options and table.concat(q.options, '\n') or nil },
    }, { allowCancel = true })
    if not input then return end
    local opts = {}
    for line in tostring(input[6] or ''):gmatch('[^\r\n,]+') do
        local o = line:gsub('^%s+', ''):gsub('%s+$', '')
        if o ~= '' then opts[#opts + 1] = o end
    end
    if input[2] == 'select' and #opts < 2 then return notify('A list needs at least 2 options.', 'error') end
    return { label = input[1], type = input[2], required = input[3] == true, min = input[4], max = input[5],
             options = input[2] == 'select' and opts or nil }
end

openQuestions = function(job, field)
    local st = lib.callback.await('bp_jobs:getSettings', false, job)
    if not st or not st.ok then return notify(st and st.reason or Config.Text.noAccess, 'error') end
    local list = field == 'promo' and st.promo or st.questions
    local default = field == 'promo' and st.defaults.promotion or st.defaults.hire
    local kindName = field == 'promo' and 'Promotion questions' or 'Application questions'
    local function commit(newList, msg) save(job, field, newList, msg) openQuestions(job, field) end

    local options = {}
    if #list == 0 then
        options[#options + 1] = { title = ('Using template "%s"'):format(default), icon = 'circle-info', readOnly = true,
            description = 'Add a question or load a template to make your own.' }
    end
    options[#options + 1] = { title = 'Add question', icon = 'plus', disabled = #list >= Config.MaxQuestions,
        onSelect = function()
            local q = questionDialog()
            if not q then return openQuestions(job, field) end
            list[#list + 1] = q
            commit(list, 'Question added.')
        end }
    options[#options + 1] = { title = 'Load template', description = 'Replace these questions with a suggested set', icon = 'file-import', arrow = true,
        onSelect = function()
            local t = {}
            for _, tpl in ipairs(st.templates) do
                t[#t + 1] = { title = tpl.name, description = ('%d questions'):format(tpl.count), icon = 'file-lines', onSelect = function()
                    local c = lib.alertDialog({ header = 'Load template?', content = ('Replace the current questions with **%s**?'):format(tpl.name), centered = true, cancel = true })
                    if c ~= 'confirm' then return openQuestions(job, field) end
                    local qs = lib.callback.await('bp_jobs:template', false, tpl.name)
                    if qs then commit(qs, ('Template "%s" loaded. Edit it however you like.'):format(tpl.name)) end
                end }
            end
            lib.registerContext({ id = 'bp_jobs_templates', title = 'Templates', menu = 'bp_jobs_questions', options = t })
            lib.showContext('bp_jobs_templates')
        end }
    options[#options + 1] = { title = 'Preview', description = 'See the form the way applicants see it', icon = 'eye',
        onSelect = function()
            local qs = #list > 0 and list or lib.callback.await('bp_jobs:template', false, default) or {}
            if #qs > 0 then lib.inputDialog('Preview: ' .. st.label, buildRows(qs), { allowCancel = true, size = 'md' }) end
            openQuestions(job, field)
        end }

    for i, q in ipairs(list) do
        options[#options + 1] = { title = ('%d. %s'):format(i, q.label), description = describe(q), icon = 'circle-question', arrow = true,
            onSelect = function()
                local sub = {
                    { title = 'Edit', icon = 'pen', onSelect = function()
                        local nq = questionDialog(q)
                        if not nq then return openQuestions(job, field) end
                        list[i] = nq
                        commit(list, 'Question updated.')
                    end },
                    { title = 'Move up', icon = 'arrow-up', disabled = i == 1, onSelect = function()
                        list[i], list[i - 1] = list[i - 1], list[i]
                        commit(list, 'Moved.')
                    end },
                    { title = 'Move down', icon = 'arrow-down', disabled = i == #list, onSelect = function()
                        list[i], list[i + 1] = list[i + 1], list[i]
                        commit(list, 'Moved.')
                    end },
                    { title = 'Delete', icon = 'trash', iconColor = '#ef4444', onSelect = function()
                        table.remove(list, i)
                        commit(list, 'Question deleted.')
                    end },
                }
                lib.registerContext({ id = 'bp_jobs_question', title = q.label, menu = 'bp_jobs_questions', options = sub })
                lib.showContext('bp_jobs_question')
            end }
    end
    if #list > 0 then
        options[#options + 1] = { title = 'Reset to default template', icon = 'rotate-left', iconColor = '#ef4444', onSelect = function()
            local c = lib.alertDialog({ header = 'Remove all questions?', content = ('%s will go back to the default template "%s".'):format(st.label, default), centered = true, cancel = true })
            if c == 'confirm' then commit({}, 'Questions reset.') else openQuestions(job, field) end
        end }
    end

    lib.registerContext({ id = 'bp_jobs_questions', title = ('%s · %s'):format(kindName, st.label), menu = 'bp_jobs_settings', options = options })
    lib.showContext('bp_jobs_questions')
end

openSettings = function(job, backMenu)
    local st = lib.callback.await('bp_jobs:getSettings', false, job)
    if not st or not st.ok then return notify(st and st.reason or Config.Text.noAccess, 'error') end
    local back = function() openSettings(job, backMenu) end

    local options = { {
        title = 'Decision roles', icon = 'user-shield',
        description = #st.roles > 0 and (#st.roles .. ' role(s): ' .. table.concat(st.roles, ', '))
            or (job == '*' and 'None. Roles here can decide on EVERY job.' or 'None yet. Only bosses / All-jobs roles can decide.'),
        onSelect = function()
            local input = lib.inputDialog('Decision roles · ' .. st.label, {
                { type = 'textarea', label = 'Discord role IDs', autosize = true, default = table.concat(st.roles, '\n'),
                  description = 'People with ANY of these roles can Accept/Deny. One per line. Discord: Server Settings > Roles > right-click > Copy Role ID' },
            }, { allowCancel = true })
            if input then save(job, 'roles', input[1], 'Decision roles saved.') end
            back()
        end,
    } }
    if job ~= '*' then
        options[#options + 1] = {
            title = 'Job logs channel', icon = 'scroll',
            description = st.logs and ('Channel ' .. st.logs) or 'Optional. Logs for this job only (e.g. in the job\'s own Discord)',
            onSelect = function()
                local input = lib.inputDialog('Logs channel · ' .. st.label, {
                    { type = 'input', label = 'Discord channel ID', default = st.logs, description = 'Leave empty to turn off' },
                }, { allowCancel = true })
                if input then save(job, 'logs', input[1] or '', 'Logs channel saved.') end
                back()
            end,
        }
        options[#options + 1] = { title = 'Application questions', icon = 'list-check', arrow = true,
            description = #st.questions > 0 and (#st.questions .. ' questions') or ('Using template "' .. st.defaults.hire .. '"'),
            onSelect = function() openQuestions(job, 'questions') end }
        if Config.Promotions.enabled then
            options[#options + 1] = { title = 'Promotion questions', icon = 'arrow-trend-up', arrow = true,
                description = #st.promo > 0 and (#st.promo .. ' questions') or ('Using template "' .. st.defaults.promotion .. '"'),
                onSelect = function() openQuestions(job, 'promo') end }
        end
    end
    lib.registerContext({ id = 'bp_jobs_settings', title = 'Job settings · ' .. st.label, menu = backMenu, options = options })
    lib.showContext('bp_jobs_settings')
end

local function openMain()
    local data = lib.callback.await('bp_jobs:menu', false)
    if not data or not data.ok then return notify(Config.Text.noAccess, 'error') end
    local options = {
        { title = 'Interview peds', description = ('%d placed'):format(#data.peds), icon = 'user-tie', arrow = true, onSelect = openManager },
    }
    if data.admin then
        options[#options + 1] = { title = 'Job settings', description = 'Roles, logs and questions per job', icon = 'gears', arrow = true,
            onSelect = function()
                local jobs = { { title = 'All jobs', description = 'Roles that can decide on every job', icon = 'globe',
                    onSelect = function() openSettings('*', 'bp_jobs_jobs') end } }
                for _, j in ipairs(data.jobs) do
                    jobs[#jobs + 1] = { title = j.label, icon = 'briefcase', onSelect = function() openSettings(j.value, 'bp_jobs_jobs') end }
                end
                lib.registerContext({ id = 'bp_jobs_jobs', title = 'Pick a job', menu = 'bp_jobs_main', options = jobs })
                lib.showContext('bp_jobs_jobs')
            end }
    else
        local j = data.jobs[1]
        options[#options + 1] = { title = 'Job settings · ' .. j.label, description = 'Roles, logs and questions', icon = 'gears', arrow = true,
            onSelect = function() openSettings(j.value, 'bp_jobs_main') end }
    end
    lib.registerContext({ id = 'bp_jobs_main', title = 'Job Center', options = options })
    lib.showContext('bp_jobs_main')
end

RegisterCommand(Config.Command, openMain, false)
TriggerEvent('chat:addSuggestion', '/' .. Config.Command, 'Job Center: interview peds, roles and questions')
