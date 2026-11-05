fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bp_jobs'
author 'Blueprint'
description 'Job applications with interview peds, Discord accept/deny and SQL saving (Standalone, QBCore, Qbox, ESX)'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'bp_discord',
}
