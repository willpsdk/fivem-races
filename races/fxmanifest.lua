fx_version 'cerulean'
game 'gta5'

author 'willpsdk'
description 'All-in-one multi-race framework'
version '4.0.0'

ui_page 'ui/index.html'

files {
    'races.json',
    'props.json',
    'ui/index.html',
    'ui/style.css',
    'ui/fonts.css',
    'ui/app.js',
    'ui/countdown.html',
    'ui/countdown.css',
    'ui/countdown.js',
    'ui/checkpoint.css',
    'ui/checkpoint.js',
    'ui/leaderboard.css',
    'ui/leaderboard.js',
    'ui/player-leaderboard.css',
    'ui/player-leaderboard.js',
    'ui/images/5.png',
    'ui/images/4.png',
    'ui/images/3.png',
    'ui/images/2.png',
    'ui/images/1.png',
    'ui/images/Go.png',
    'ui/images/leader.png',
    'ui/fonts/Mont-HeavyDEMO.otf',
    'bin/MenuAPI.dll'
}

client_scripts {
    'client.lua'
}

client_script 'bin/races.net.dll'

server_scripts {
    'server.lua'
}
