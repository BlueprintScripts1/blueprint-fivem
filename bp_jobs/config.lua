Config = {}

-- ───────────────────────── Framework ─────────────────────────
-- 'auto' detects it: qbx_core -> 'qbox', qb-core -> 'qbcore', es_extended -> 'esx', none -> 'standalone'
Config.Framework = 'auto'

-- Only used in standalone mode (no framework): bp_jobs keeps its own jobs, saved in the bp_standalone_jobs table.
-- Other scripts can read/set them: exports.bp_jobs:GetJob(src) / exports.bp_jobs:SetJob(src, job, grade)
Config.Standalone = {
    DefaultJob = 'unemployed',
    Jobs = {
        unemployed = { label = 'Civilian', grades = { [0] = { name = 'Unemployed' } } },
        mechanic = { label = 'Mechanic', grades = {
            [0] = { name = 'Recruit' }, [1] = { name = 'Mechanic' }, [2] = { name = 'Manager', isboss = true },
        } },
        police = { label = 'Police', grades = {
            [0] = { name = 'Cadet' }, [1] = { name = 'Officer' }, [2] = { name = 'Sergeant' }, [3] = { name = 'Chief', isboss = true },
        } },
        ambulance = { label = 'EMS', grades = {
            [0] = { name = 'Trainee' }, [1] = { name = 'Paramedic' }, [2] = { name = 'Doctor' }, [3] = { name = 'Chief', isboss = true },
        } },
    },
}

-- ───────────────────────── Discord ─────────────────────────
-- Main logs channel: every application, decision and change is logged here.
-- Each job can ALSO get its own logs channel in-game (/jobcenter > Job settings).
Config.LogsChannel = '000000000000000000'

-- Who can accept/deny is set IN-GAME per job (/jobcenter > Job settings > Decision roles),
-- so EMS staff decide in the EMS Discord, police in the police Discord, and so on.
-- 'All jobs' roles (admins only) work for every job.

-- In-game bosses of a job can accept/deny on Discord too (their Discord is linked when they join)
Config.BossesDecideOnDiscord = true

-- DM the applicant on Discord when accepted/denied (silently skipped if their DMs are closed)
Config.DMApplicant = true

-- Players without Discord open in FiveM can't apply
Config.RequireDiscord = true

Config.Colors = { pending = 0x3B82F6, accepted = 0x22C55E, denied = 0xEF4444, log = 0x64748B }

Config.Emojis = {
    template = '📝',
    check = '✅',
    cross = '❌',
    staff = '🛠️',
    star = '⭐',
    arrow = '➜',
    bell = '🔔',
    -- Button emojis. Unicode: { name = '✅' } · Custom server emoji: { id = '123456789012345678', name = 'my_emoji' }
    btnAccept = { name = '✅' },
    btnDeny = { name = '✖️' },
}

-- ───────────────────────── Who can use /jobcenter ─────────────────────────
-- 'boss'  = admins for any job + every boss for their own job (peds, roles, questions)
--           boss = QBCore/Qbox isboss grade, ESX grade named 'boss', standalone isboss grade
-- 'admin' = admins only
Config.PedAccess = 'boss'
-- QBCore/Qbox permissions or ESX groups that count as admin. The ace 'bp_jobs.admin' works on every framework (and is the only way in standalone)
Config.AdminPermissions = { 'god', 'admin', 'superadmin' }
Config.Command = 'jobcenter' -- opens the in-game menu (peds + job settings + questions)

-- ───────────────────────── Applying ─────────────────────────
-- People in these jobs can't apply anywhere else (they can still apply for a promotion in their own job)
Config.Blacklist = {
    police = true,
    ambulance = true,
    -- sheriff = true,
    -- doj = true,
}

Config.HireGrade = 0           -- grade given when a hire application is accepted
Config.CooldownHours = 24      -- after a denial, wait this long before applying to the same job again
Config.MaxDistance = 6.0       -- anti-cheat: must stand this close to the ped to submit

Config.Promotions = {
    enabled = true,            -- people already in the job get a promotion application instead
    bossesCanApply = false,    -- bosses can't request promotions
}

-- ───────────────────────── Questions ─────────────────────────
-- Questions are made IN-GAME per job (/jobcenter > Job settings > Application / Promotion questions).
-- These are only suggested templates: load one in-game with "Load template", then edit it.
-- A job with no questions of its own uses the DefaultTemplates below.
Config.MaxQuestions = 10
Config.DefaultTemplates = { hire = 'General', promotion = 'Promotion' }

-- Types: 'input', 'textarea', 'number', 'select' (needs options). min / max = characters for text, value for numbers
Config.QuestionTemplates = {
    ['General'] = {
        { label = 'How old is your character?', type = 'number', min = 16, max = 99 },
        { label = 'Why do you want this job?', type = 'textarea', min = 20, max = 600 },
        { label = 'Any previous experience?', type = 'textarea', min = 5, max = 600 },
        { label = 'How many hours a week can you work?', type = 'number', min = 1, max = 168 },
        { label = 'When are you usually online?', type = 'select', options = { 'Mornings', 'Afternoons', 'Evenings', 'Nights', 'Weekends only' } },
    },
    ['Police'] = {
        { label = 'How old is your character?', type = 'number', min = 18, max = 99 },
        { label = 'Does your character have a criminal record?', type = 'select', options = { 'No', 'Yes, minor', 'Yes, serious' } },
        { label = 'Why do you want to join the police?', type = 'textarea', min = 30, max = 600 },
        { label = 'A suspect flees on foot into a crowd. What do you do?', type = 'textarea', min = 30, max = 600 },
        { label = 'Any previous law enforcement RP experience?', type = 'textarea', min = 5, max = 600 },
        { label = 'When are you usually online?', type = 'select', options = { 'Mornings', 'Afternoons', 'Evenings', 'Nights', 'Weekends only' } },
    },
    ['EMS'] = {
        { label = 'How old is your character?', type = 'number', min = 18, max = 99 },
        { label = 'Why do you want to join EMS?', type = 'textarea', min = 30, max = 600 },
        { label = 'You arrive at a crash with 3 injured people. Who do you treat first and why?', type = 'textarea', min = 30, max = 600 },
        { label = 'Any previous medical RP experience?', type = 'textarea', min = 5, max = 600 },
        { label = 'Can you stay neutral and help everyone, including criminals?', type = 'select', options = { 'Yes', 'No' } },
    },
    ['Mechanic'] = {
        { label = 'How old is your character?', type = 'number', min = 16, max = 99 },
        { label = 'Do you know how to repair engines and bodywork?', type = 'select', options = { 'Yes', 'A little', 'No, but I want to learn' } },
        { label = 'Why should we hire you?', type = 'textarea', min = 20, max = 600 },
        { label = 'How many hours a week can you work?', type = 'number', min = 1, max = 168 },
    },
    ['Business'] = {
        { label = 'How old is your character?', type = 'number', min = 16, max = 99 },
        { label = 'Why do you want to work here?', type = 'textarea', min = 20, max = 600 },
        { label = 'How would you handle a rude customer?', type = 'textarea', min = 20, max = 600 },
        { label = 'When are you usually online?', type = 'select', options = { 'Mornings', 'Afternoons', 'Evenings', 'Nights', 'Weekends only' } },
    },
    ['Promotion'] = {
        { label = 'Why do you deserve a promotion?', type = 'textarea', min = 20, max = 600 },
        { label = 'What have you done for the business lately?', type = 'textarea', min = 10, max = 600 },
        { label = 'What will you do differently in the new rank?', type = 'textarea', min = 10, max = 600, required = false },
    },
}

-- ───────────────────────── Peds ─────────────────────────
Config.Interaction = 'ox_target' -- 'ox_target' | 'qb-target' | 'textui' (press E)
Config.SpawnDistance = 60.0
Config.DefaultPedModel = 'a_m_y_business_03'
Config.Scenarios = {
    { value = 'WORLD_HUMAN_CLIPBOARD', label = 'Holding clipboard' },
    { value = 'WORLD_HUMAN_STAND_IMPATIENT', label = 'Standing' },
    { value = 'WORLD_HUMAN_AA_COFFEE', label = 'Drinking coffee' },
    { value = 'WORLD_HUMAN_SMOKING', label = 'Smoking' },
    { value = 'WORLD_HUMAN_COP_IDLES', label = 'Guard idle' },
    { value = 'none', label = 'No animation' },
}

Config.Blip = { enabled = true, sprite = 408, color = 3, scale = 0.7 }

-- ───────────────────────── Texts ─────────────────────────
Config.Text = {
    target = 'Job interview: %s',
    textui = '[E] Job interview: %s',
    noDiscord = 'Open Discord before launching FiveM so we can link your application.',
    blacklisted = 'You can\'t apply while working as %s.',
    alreadyMax = 'You\'re already at the highest rank here.',
    bossNoPromo = 'Bosses can\'t request promotions.',
    pending = 'You already have a pending application here.',
    cooldown = 'Your last application here was denied. Try again later.',
    closed = 'This desk isn\'t taking applications right now.',
    sent = 'Application sent! You\'ll be notified when it\'s reviewed.',
    offline = 'Applications are offline right now, try again later.',
    accepted = 'Your application for %s was accepted!',
    promoted = 'Your promotion request for %s was accepted! New rank: %s',
    denied = 'Your application for %s was denied.',
    noAccess = 'You don\'t have access to this.',
}
