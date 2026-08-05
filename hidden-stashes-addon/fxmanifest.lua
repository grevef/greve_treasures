-- By using this script, you agree to the EULA provided by LuckyyFishyy

fx_version 'cerulean'
game 'gta5'

author 'LuckyyFishyy'
description 'Buried hidden stashes for Qbox'
version '1.0.0'

lua54 'yes'

-- Main
client_scripts {
    'client/main.lua',
}

-- Server
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

-- Config
shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

-- HTML
files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql'
}
