-- ============================================
-- whip_afk — who is away from the keys (server)
-- ============================================
--
-- The player's game notices no input for a while (client/main.lua) and says so here; this puts it on their bag
-- under the Sentinel's watch (RegisterSentinelKey), so it is the server's word and not one a client wrote itself.
-- Every game reads the bag (the AFK tag over their head), and so can any other resource:
--
--     local since = Player(src).state.whip_afk     -- os.time() at their last input, or nil while they play
--     AddEventHandler('whip_afk:changed', function(e) ... e.source, e.afk ... end)
--
-- The value is the moment of their LAST INPUT, not the moment they were marked: a player marked after a minute has
-- been away a minute already. Cleared when they come back, die, log out to character select or leave.

KEY = 'whip_afk'
local MAX_IDLE_MS = 24 * 60 * 60 * 1000

local function set(src, value)
    local had = Player(src).state[KEY] ~= nil
    if (value ~= nil) == had then return end
    Whip.core:SetSentinelPlayerKey(src, KEY, value)
    TriggerEvent('whip_afk:changed', { source = src, afk = value ~= nil })
end

Whip.register(function()
    Whip.core:RegisterSentinelKey({ key = KEY, family = 'player' })

    Whip.core:SecureEvent('whip_afk:set', {
        whileDead = true,   -- coming back is always heard, even from a death
        rateLimit = 1000,
        burst     = 4,
        params    = { { 'away', 'bool' }, { 'idleMs', 'int', 0, MAX_IDLE_MS, 0 } },
    }, function(source, _, away, idleMs)
        if not away then return set(source, nil) end
        if Config.Enabled == false or Whip.core:IsPlayerDead(source) then return false end
        set(source, os.time() - math.floor(idleMs / 1000))
    end)
end)

-- Logging out to character select: whoever they become next starts at their keys.
AddEventHandler('whip_core:player:logout', function(e)
    if type(e) == 'table' and tonumber(e.source) then set(tonumber(e.source), nil) end
end)

-- Turned off in /whip → Settings: nobody stays marked.
Whip.onConfigChanged('Enabled', function(on)
    if on ~= false then return end
    for _, idStr in ipairs(GetPlayers()) do
        local id = tonumber(idStr)
        if id then set(id, nil) end
    end
end)

Whip.sayStarted()
