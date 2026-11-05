local function notify(msg, kind)
    lib.notify({ title = 'Duty', description = msg, type = kind or 'inform', duration = 7000 })
end

local openMenu

local function deptMenu(d)
    local options = {
        { title = 'Logs channel', icon = 'scroll',
          description = d.logs and ('Channel ' .. d.logs) or 'Not set. On/off duty logs for this department',
          onSelect = function() openMenu(d.job, 'edit') end },
        { title = 'Panel channel', icon = 'table-list',
          description = d.panel and ('Channel ' .. d.panel .. (d.showNames and ' · with names' or ' · counts only')) or 'Not set. A live panel showing only this department',
          onSelect = function() openMenu(d.job, 'edit') end },
        { title = 'Send test message', icon = 'paper-plane', description = 'Checks the bot can post in both channels',
          onSelect = function()
              local r = lib.callback.await('bp_status:testDepartment', false, d.job)
              notify(r and r.reason or 'Failed.', r and r.ok and 'success' or 'error')
              openMenu(d.job)
          end },
    }
    if d.configLogs then
        options[#options + 1] = { title = 'Also logging to config channel', description = d.configLogs, icon = 'circle-info', readOnly = true }
    end
    lib.registerContext({ id = 'bp_status_dept', title = ('%s %s'):format(d.emoji, d.label), menu = 'bp_status_list', options = options })
    lib.showContext('bp_status_dept')
end

local function editDialog(d)
    local input = lib.inputDialog(('%s %s · Discord channels'):format(d.emoji, d.label), {
        { type = 'input', label = 'Logs channel ID', default = d.logs, description = 'On/off duty logs. Leave empty to turn off' },
        { type = 'input', label = 'Panel channel ID', default = d.panel, description = 'Live panel for this department only. Leave empty to turn off' },
        { type = 'checkbox', label = 'Show names on the panel', checked = d.showNames },
    }, { allowCancel = true })
    if not input then return end
    local r = lib.callback.await('bp_status:saveDepartment', false, d.job, { logs = input[1], panel = input[2], showNames = input[3] == true })
    if r and r.ok then notify('Saved. The panel updates in a few seconds.', 'success') else notify(r and r.reason or 'Failed.', 'error') end
end

openMenu = function(focusJob, action)
    local list = lib.callback.await('bp_status:departments', false)
    if not list or #list == 0 then return notify('You don\'t have access to any department.', 'error') end
    if focusJob then
        for _, d in ipairs(list) do
            if d.job == focusJob then
                if action == 'edit' then editDialog(d) return openMenu(focusJob) end
                return deptMenu(d)
            end
        end
    end
    if #list == 1 then return deptMenu(list[1]) end
    local options = {}
    for _, d in ipairs(list) do
        options[#options + 1] = { title = ('%s %s'):format(d.emoji, d.label), arrow = true,
            description = ('Logs: %s · Panel: %s'):format(d.logs and 'set' or 'off', d.panel and 'set' or 'off'),
            onSelect = function() deptMenu(d) end }
    end
    lib.registerContext({ id = 'bp_status_list', title = 'Departments', options = options })
    lib.showContext('bp_status_list')
end

RegisterCommand(Config.SettingsCommand, function() openMenu() end, false)
TriggerEvent('chat:addSuggestion', '/' .. Config.SettingsCommand, 'Department Discord channels for duty logs and panels')
