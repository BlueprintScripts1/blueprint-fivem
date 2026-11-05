fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bp_status'
author 'Blueprint'
description 'Live Discord server status panel and duty tracking (QBCore demo, departments, multi-character)'
version '0.2.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_script 'client/main.lua'

dependencies {
    'qb-core',
    'oxmysql',
    'ox_lib',
    'bp_discord',
}
