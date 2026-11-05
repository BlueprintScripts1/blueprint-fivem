# bp_jobs: Job Applications (Standalone · QBCore · Qbox · ESX)

Players walk up to an interview ped, answer the questions, and the application lands in that job's Discord channel with **Accept / Deny** buttons.
Everything (peds, decision roles, logs channels, questions) is set **in-game**, so every job can use its own Discord server: EMS applications in the EMS Discord, police in the police Discord, and so on.

## Requirements
- `ox_lib`, `oxmysql`
- A framework is optional: **QBCore**, **Qbox** or **ESX** is detected automatically (`Config.Framework = 'auto'`). With none, it runs **standalone**.
- `bp_discord` (included, with its own README). It runs its own bot, or uses **your own bot** through the Bot Bridge
- `ox_target` or `qb-target`, or neither with `Config.Interaction = 'textui'` (press E)

## Install
1. Put `bp_jobs` and `bp_discord` in your resources.
2. Set up the bot and its token, following `bp_discord/README.md`.
3. In `server.cfg`, in this order:
```cfg
ensure oxmysql
ensure ox_lib
ensure qb-core          # or qbx_core / es_extended / nothing for standalone
ensure ox_target
ensure bp_discord
ensure bp_jobs

add_ace group.admin bp_jobs.admin allow   # admins on any framework (required for standalone)
```
4. Set `Config.LogsChannel` in `config.lua` (the main logs channel).
5. Restart. The console prints the detected framework (`[bp_jobs] Framework: qbcore`). The SQL tables are created automatically (`sql.sql` is included if you'd rather import by hand).

## Frameworks
| | Character / ID | Boss | Admin | Hire / promote offline |
|---|---|---|---|---|
| **QBCore** | charinfo name, `citizenid` | grade with `isboss` | `Config.AdminPermissions` (`god`, `admin`) | writes `players.job` |
| **Qbox** | charinfo name, `citizenid` | grade with `isboss` | Qbox permissions / aces | `AddPlayerToJob` + `SetPlayerPrimaryJob` |
| **ESX** | `getName()`, `identifier` | grade named `boss` | group `admin` / `superadmin` | writes `users.job`, `users.job_grade` |
| **Standalone** | FiveM name, license | grade with `isboss` in `Config.Standalone.Jobs` | ace `bp_jobs.admin` | own table `bp_standalone_jobs` |

Force one with `Config.Framework = 'qbcore' | 'qbox' | 'esx' | 'standalone'`.

**Standalone jobs** are defined in `Config.Standalone.Jobs` and saved per player (license). Other scripts can use them:
```lua
local job = exports.bp_jobs:GetJob(source)          -- { name, label, level, isboss }
exports.bp_jobs:SetJob(source, 'mechanic', 1)
AddEventHandler('bp_jobs:jobChanged', function(src, job, grade) end)          -- server
RegisterNetEvent('bp_jobs:jobChanged', function(job, grade) end)              -- client
```

## /jobcenter (the in-game menu)
Who can open it:
- **Admins:** see the Frameworks table, or anyone with the ace `bp_jobs.admin`. They manage every job.
- **Bosses**, when `Config.PedAccess = 'boss'`. They manage only their own job.
  Set `Config.PedAccess = 'admin'` for admins only.

### Interview peds
- **Add interview ped here:** choose the job, desk name, ped model, **Discord channel ID** (where this ped's applications go) and animation. The ped spawns where you stand, facing your direction.
- Click a ped to:
  - **Edit** it
  - **Move to my position**
  - **Send test message**: checks the bot can post in the channel
  - **Close/Open** applications
  - **Teleport** to it (admins only)
  - **Delete** it

One job can have several peds, even in different channels.

### Job settings
| Setting | What |
|---|---|
| **Decision roles** | Discord role IDs that can Accept/Deny this job's applications (paste them one per line). Role IDs work in whichever Discord server they belong to |
| **Job logs channel** | Optional: this job's logs also go here (for example in the job's own Discord). The main `Config.LogsChannel` always gets everything |
| **Application questions** | The questions for people applying to join |
| **Promotion questions** | The questions for people already in the job asking for the next rank |
| **All jobs** (admins only) | Decision roles that work on **every** job, for city staff |

The job's in-game **bosses** can always decide on Discord too (`Config.BossesDecideOnDiscord`).

### Question editor
- **Add question:** the question text, plus:
  - an answer type: short text, long text, number, or pick from a list
  - whether it's required
  - min and max (characters for text, the value for numbers)
  - list options, one per line
- Click a question to **Edit**, **Move up / down**, or **Delete** it.
- **Load template** replaces the questions with a suggested set, which you can then edit.
- **Preview** opens the exact form applicants will see.
- **Reset to default template** removes your own questions.
- Up to `Config.MaxQuestions` (10).

A job with no questions of its own uses `Config.DefaultTemplates` (**General** for applications, **Promotion** for promotions).
The templates (General, Police, EMS, Mechanic, Business, Promotion) live in `Config.QuestionTemplates`. Add your own there and they show up under **Load template**.

## How applying works
1. Player → ped → **Job interview** → answers → confirm.
2. Checked first:
   - Discord must be open, so the application can link to them.
   - Players in a **blacklisted job** (`Config.Blacklist`: police, ambulance...) can't apply elsewhere.
   - Already in this job means a **promotion request** to the next grade instead. Bosses and max-rank players are blocked.
   - Only one pending application per job.
   - `Config.CooldownHours` must pass after a denial.
3. The Discord message shows:
   - **Character name and CitizenID**
   - **FiveM name**
   - **Discord** mention and ID
   - **Steam profile and Steam64**
   - Phone and current job
   - Every answer
4. **Accept** gives the job, or the next grade for a promotion, even if the player is **offline** (they're told when they next load in).
   **Deny** asks for an optional reason.
5. The message updates with who decided. The player gets an in-game notification and a Discord DM, and the decision is logged.

Two staff clicking at once, or double clicks, are safe: only the first decision counts. Nobody can decide on their own application.

## config.lua
| Setting | Default | What |
|---|---|---|
| `Framework` | `'auto'` | `auto`, `qbcore`, `qbox`, `esx`, `standalone` |
| `Standalone` | | Jobs and default job for standalone mode |
| `AdminPermissions` | `god`, `admin`, `superadmin` | Admin permissions / ESX groups |
| `LogsChannel` | – | Main logs channel ID |
| `BossesDecideOnDiscord` | `true` | In-game bosses can Accept/Deny their job on Discord |
| `DMApplicant` | `true` | DM the result to the applicant |
| `RequireDiscord` | `true` | Must have Discord open to apply |
| `PedAccess` | `'boss'` | `'boss'` or `'admin'` (who can use /jobcenter) |
| `Command` | `'jobcenter'` | Menu command |
| `Blacklist` | police, ambulance | Jobs that can't apply elsewhere |
| `HireGrade` | `0` | Grade given on accept |
| `CooldownHours` | `24` | Wait after a denial |
| `Promotions` | on | Promotion requests for people already in the job |
| `QuestionTemplates` / `DefaultTemplates` | | Suggested questions |
| `Interaction` | `'ox_target'` | `ox_target`, `qb-target` or `textui` |
| `Emojis` | Unicode | Emojis in the messages and buttons. Swap in your own server emojis if you like |
| `Blip`, `Scenarios`, `DefaultPedModel`, `Colors`, `Text` | | Looks and texts |

## SQL tables
| Table | Saves |
|---|---|
| `bp_applications` | Every application: citizenid, character name, FiveM name, Discord, Steam, Steam64, license, phone, current job, target grade, answers (JSON), status, deny reason, who decided, message ID, dates |
| `bp_application_peds` | Every ped: job, name, model, animation, position, channel ID, open/closed, who placed it |
| `bp_job_settings` | Per job: decision roles, logs channel, application and promotion questions (`*` = all jobs) |
| `bp_identities` | CitizenID ↔ Discord / Steam / license, refreshed every login |
| `bp_application_logs` | Every action |
| `bp_standalone_jobs` | Standalone mode only: each player's job and grade |

## Troubleshooting
| Problem | Fix |
|---|---|
| "Applications are offline right now" | The bot can't post in that ped's channel. Use **Send test message** in /jobcenter, and check the server console for the Discord error |
| Accept says "You can't decide on ... applications" | Add your role under **Job settings → Decision roles**, or under **All jobs** |
| "Open Discord before launching FiveM" | The player must have the Discord app open when starting FiveM. Turn off with `Config.RequireDiscord = false` |
| /jobcenter says no access | You need admin (see Frameworks), the `bp_jobs.admin` ace, or be a boss (with `PedAccess = 'boss'`) |
| Wrong framework detected | Set `Config.Framework` by hand |
