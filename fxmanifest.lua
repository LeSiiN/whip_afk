fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whip_afk'
description 'AFK for whip: players with no input for a while are marked away. Others see an AFK tag over their head; their own camera shows off the car they sit in, or makes a portrait of them on foot, while their character does what fits where they are. Any key brings them back.'
author 'LeSiiN'
version '1.0.0'
whip_updates 'LeSiiN/whip_afk'   -- whip_core checks this repository's releases for a newer version

-- Everything goes through whip_core's exports and its satellite helpers (Whip.register, Whip.configPage,
-- Whip.playerSetting). The camera maths, the world quads and the DUI pages are whip_core's own files, loaded here
-- as whip_fuel loads world_quad.lua: one implementation of each.
dependency 'whip_core'
whip_requires '1.0'

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
    'shared/settings.lua',          -- config.lua as a page in /whip → Settings → AFK
}

client_scripts {
    '@whip_core/lib/cost.lua',             -- /whipcost times our sections too
    '@whip_core/shared/cam_math.lua',      -- the camera maths: the walls test plays our shots the way the camera will
    '@whip_core/shared/cam_sequence.lua',
    '@whip_core/client/cam_shots.lua',
    '@whip_core/client/world_quad.lua',    -- the AFK tag over a head, drawn as whip's /me bubbles are
    '@whip_core/client/dui_page.lua',
    'client/prefs.lua',      -- each player's own choices (the pause menu's Server Settings → AFK)
    'client/showroom.lua',   -- the camera while away: the car shown off, or a portrait on foot
    'client/idle.lua',       -- what the character does while away
    'client/tags.lua',       -- the AFK tag over the heads of others who are away
    'client/main.lua',       -- noticing no input, being away, coming back
}

server_script 'server/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/afk.css',
    'html/afk.js',
    'html/tag.html',
}
