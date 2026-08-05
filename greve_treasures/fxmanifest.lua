fx_version 'cerulean'
game 'gta5'

author 'Greve'
description 'Hidden Stashes'
version '3.0.0'

lua54 'yes'

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql'
}
