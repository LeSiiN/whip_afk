-- ============================================
-- whip_afk — away from the keys (client)
-- ============================================
--
-- NOTICING. Once a second, never every frame: a look at what input would have changed since the last look. The
-- camera turned (relative to the player, so a car turning under it does not count), the player moved or turned,
-- the vehicle moved, a key that is held right now (the brake at a light), or a switch between keyboard and pad.
-- Anything a player does shows in one of those, or opens something (a screen, the pause menu, the chat's focus),
-- which counts too. A tap between two looks that changes none of them is missed, and does not matter: the player
-- is still there a second later and does something else. Config.Delay seconds (or the player's own, the pause
-- menu's) of none of it, while nothing else is going on (dead, in a fight, wanted, another camera up, a screen
-- open), and they are away.
--
-- AWAY. The server is told (server/main.lua) and puts it on their bag, which every game reads: the AFK tag over
-- their head (client/tags.lua). In a vehicle standing still, their own camera shows the car off; on foot their
-- character does what fits where they stand (client/idle.lua) and the camera makes a portrait of them once that has
-- settled (client/showroom.lua). Config.Ghost: see-through and nothing bumps them, while away.
--
-- BACK. While away, and only then, a loop of our own runs every frame and asks whether any key went down, the mouse
-- or a stick moved, or something opened: at the first, they are back. The camera blends home over half a second,
-- the HUD returns, the server is told. The same loop gives the showroom its soft cuts. Whatever they were doing ends
-- the way the game ends it (standing up, the phone away), and their movement is held until it has (Idle.stop's
-- check): they get up before they walk off. Then a card says welcome back, how long they were away, and shows the
-- showroom's photo.
--
-- For other resources: the bag (`Player(id).state.whip_afk`, os.time() at their last input) and the local event
-- whip_afk:changed { afk, showroom } on this game.

local POLL_MS   = 1000
local LOOK_DEG  = 0.75    -- the camera turning this much (relative to the player) between two looks is input
local MOVE_M    = 0.15    -- the player moving this far between two looks
local TURN_DEG  = 3.0     -- the player turning this much
local STILL_MS  = 0.5     -- m/s: a vehicle slower than this stands still (for the showroom)
local ROLL_MS   = 1.5     -- m/s: while away, a vehicle faster than this has been moved: they are back
local MOUSE_MIN = 0.003   -- while away: a mouse's look reading past this is a hand on it
local STICK_MIN = 0.25    -- ...and a stick's past this (a worn stick drifts under it)
local HURT_HP   = 10      -- while away: losing more health than this (a hit) brings them back
local SCREEN_EVERY = 10   -- while away: whip's "is a screen open" (an export) asked every this many frames

--- While away: a key going down here is input. The player's world keys (on foot and in a vehicle), the phone's,
--- the menus' and the chat's; a pad's buttons are these controls too.
local KEYS = {
    21, 22, 23, 24, 25, 36, 37, 38, 44, 45, 47, 51, 52, 68, 69, 70, 71, 72, 73, 74, 75, 76, 80, 86, 91, 92,
    99, 100, 140, 157, 158, 160, 164, 165, 170, 172, 173, 174, 175, 176, 177, 178, 199, 200, 201, 202, 244,
    245, 246, 249, 288, 289, 303, 311, 322,
}
--- ...and one held right now, at a look: the keys a player can hold while standing still.
local HELD = { 21, 22, 24, 25, 44, 71, 72, 76, 86 }

local function enabled() return Config.Enabled ~= false end
local function loaded() return exports.whip_core:IsPlayerLoaded() == true end
local function onPad() return IsUsingKeyboard and not IsUsingKeyboard(2) or false end

-- whip's clean screen held by someone else (filming): not a moment to go away. Ours is the showroom's.
local othersClean = false
AddEventHandler('whip_core:ui:cleanScreen', function(e)
    othersClean = type(e) == 'table' and e.on == true and not Showroom.active()
end)

-- ============================================
-- This player
-- ============================================

local away = false        -- marked away (and the server told)
local lastInput = GetGameTimer()
local last = nil          -- the last look's readings
local polling = false
local ghostVeh = nil      -- the car made see-through with them (Config.Ghost)
local health = 0          -- their health as they went away: hurt while away brings them back
local awaySince = 0       -- GetGameTimer at their last input, for the welcome back card
local awayTurn = 0        -- bumped each time they go away: a portrait waiting to start, or the frame loop, checks it

local function delayMs()
    return math.max(15, tonumber(AfkPrefs.get('delay')) or tonumber(Config.Delay) or 60) * 1000
end

--- Something else is going on: not away, whatever the keys say.
local function busy(ped)
    local me = PlayerId()
    return IsEntityDead(ped) or IsPedInMeleeCombat(ped) or IsPedShooting(ped)
        or IsPlayerFreeAiming(me) or IsPedRagdoll(ped) or GetPlayerWantedLevel(me) > 0
        or IsPauseMenuActive() or IsNuiFocused() or IsScreenFadedOut() or IsScreenFadingOut()
        or IsPlayerSwitchInProgress() or othersClean
        or exports.whip_core:IsCameraActive()                        -- whip's camera is up: a cutscene, a showroom
        or not exports.whip_core:IsGameInputFree()                   -- a screen, a bar, a dialog, someone's mode
end

local function anyHeld()
    for i = 1, #HELD do
        if IsDisabledControlPressed(0, HELD[i]) then return true end
    end
    return math.abs(GetDisabledControlNormal(0, 30)) > STICK_MIN or math.abs(GetDisabledControlNormal(0, 31)) > STICK_MIN
end

--- What input would change, now.
local function read(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    local p = GetEntityCoords(ped)
    return { x = p.x, y = p.y, z = p.z, h = GetEntityHeading(ped), veh = veh,
             ch = GetGameplayCamRelativeHeading(), cp = GetGameplayCamRelativePitch(),
             speed = GetEntitySpeed(veh ~= 0 and veh or ped), pad = onPad() }
end

local function angle(a, b) return math.abs((a - b + 180.0) % 360.0 - 180.0) end

local function changed(a, b)
    if a.veh ~= b.veh or a.pad ~= b.pad then return true end
    if angle(a.ch, b.ch) > LOOK_DEG or math.abs(a.cp - b.cp) > LOOK_DEG then return true end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    if dx * dx + dy * dy + dz * dz > MOVE_M * MOVE_M then return true end
    return angle(a.h, b.h) > TURN_DEG or a.speed > STILL_MS
end

local function cameraWanted()
    return Config.Showroom ~= false and AfkPrefs.get('showroom') ~= false
end

--- May the showroom play round this vehicle now?
local function showroomFor(veh)
    if veh == 0 or not cameraWanted() then return false end
    if GetEntitySpeed(veh) > STILL_MS then return false end
    if GetVehicleClass(veh) == 14 then return true end        -- a boat lies on the water
    return not IsEntityInAir(veh)                             -- anything else on the ground, an aircraft landed
end

--- May the portrait play round them on foot now? Standing, not in the water, the air or on a ladder.
local function portraitFor(ped)
    return cameraWanted() and GetEntitySpeed(ped) < STILL_MS and not IsPedSwimming(ped) and not IsPedFalling(ped)
        and not IsPedInParachuteFreeFall(ped) and not IsPedClimbing(ped)
end

--- See-through to others, and nothing bumps them (GTA's own ghosting: the game that owns them sets it).
local function ghost(on, veh)
    if on then
        if Config.Ghost ~= true then return end
        if SetLocalPlayerAsGhost then SetLocalPlayerAsGhost(true, false) end
        if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == PlayerPedId() and NetworkHasControlOfEntity(veh)
            and SetNetworkVehicleAsGhost then
            SetNetworkVehicleAsGhost(veh, true)
            ghostVeh = veh
        end
    else
        if SetLocalPlayerAsGhost then SetLocalPlayerAsGhost(false, false) end
        if ghostVeh and DoesEntityExist(ghostVeh) and SetNetworkVehicleAsGhost then SetNetworkVehicleAsGhost(ghostVeh, false) end
        ghostVeh = nil
    end
end

local back   -- (below; the frame loop calls it)

--- One frame while away: any input, and the showroom's cuts. Answers true when they are back.
local function frame(n)
    local now = GetGameTimer()
    for i = 1, #KEYS do
        if IsDisabledControlJustPressed(0, KEYS[i]) then return true end
    end
    local look = onPad() and STICK_MIN or MOUSE_MIN
    if math.abs(GetDisabledControlNormal(0, 1)) > look or math.abs(GetDisabledControlNormal(0, 2)) > look
        or math.abs(GetDisabledControlNormal(0, 30)) > STICK_MIN or math.abs(GetDisabledControlNormal(0, 31)) > STICK_MIN
        or GetDisabledControlNormal(0, 71) > 0.1 or GetDisabledControlNormal(0, 72) > 0.1 then
        return true
    end
    if IsPauseMenuActive() or IsNuiFocused() then return true end
    if n % SCREEN_EVERY == 0 and (exports.whip_core:IsAnyScreenOpen() or not loaded()) then return true end
    local ped = PlayerPedId()
    -- Hurt (a hit, not hunger's slow ticks) brings them back.
    if IsEntityDead(ped) or GetEntityHealth(ped) < health - HURT_HP then return true end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetEntitySpeed(veh) > ROLL_MS then return true end
    if not Showroom.frame(now) then return true end
    return false
end

--- Every frame while away, and only then: ends with them.
local function frameLoop(turn)
    CreateThread(function()
        local n = 0
        while away and awayTurn == turn do
            n = n + 1
            local cost = WhipCost.start()
            local isBack = frame(n)
            WhipCost.stop('afk: away, watching for a key (every frame while away)', cost)
            if isBack then back() break end
            Wait(0)
        end
    end)
end

local function goAway(ped, idleMs)
    away = true
    awayTurn = awayTurn + 1
    awaySince = GetGameTimer() - idleMs
    health = GetEntityHealth(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    local showroom = false
    local idle = Config.IdleEmotes ~= false and AfkPrefs.get('emote') ~= false
    if veh ~= 0 then
        showroom = showroomFor(veh) and Showroom.start(veh, idleMs) or false
        if idle then Idle.startInVehicle(ped, veh) end
    else
        local wait = 0
        if idle then wait = Idle.start(ped) end
        if portraitFor(ped) then
            -- Once the pose has settled (a lean turns them, a seat moves them), so the walls test sees where they are.
            local turn = awayTurn
            SetTimeout(wait, function()
                if away and awayTurn == turn then Showroom.startOnFoot(idleMs + wait) end
            end)
            showroom = true
        end
    end
    ghost(true, veh)
    frameLoop(awayTurn)
    TriggerServerEvent('whip_afk:set', true, math.floor(idleMs))
    TriggerEvent('whip_afk:changed', { afk = true, showroom = showroom })
end

--- Their movement held until `done()` says the pose has ended (getting up from a bench, the phone put away).
--- Looking round stays free. Released by a cap too (Idle's own), so it can never stick.
local function holdForExit(done)
    exports.whip_core:BlockControls('exit', { groups = { 'move', 'combat', 'driving', 'vehicleCombat' } })
    CreateThread(function()
        while not done() do Wait(100) end
        exports.whip_core:UnblockControls('exit')
    end)
end

--- Back at the keys (or no longer allowed to be away). Fine when not away.
back = function()
    if not away then return end
    away = false
    local awayFor = GetGameTimer() - awaySince
    lastInput, last = GetGameTimer(), nil
    Showroom.stop()
    local done = Idle.stop()
    if done then holdForExit(done) end
    ghost(false)
    TriggerServerEvent('whip_afk:set', false, 0)
    TriggerEvent('whip_afk:changed', { afk = false, showroom = false })
    -- Welcome back: how long, and the showroom's photo when there is one (html/afk.js).
    if loaded() then
        SendNUIMessage({ action = 'afkBack', awayMs = math.max(0, awayFor), photo = Showroom.takePhoto() })
    end
end

--- One look. Not while away: the frame loop watches then.
local function look()
    if away then return end
    local ped = PlayerPedId()
    local now = GetGameTimer()
    if busy(ped) or anyHeld() then
        lastInput, last = now, nil
        return
    end
    local r = read(ped)
    if not last or changed(r, last) then lastInput = now end
    last = r
    local idle = now - lastInput
    if idle < delayMs() then return end
    -- Standing still is part of being away in a vehicle: a car rolling or flying is someone's doing.
    if r.veh ~= 0 and (r.speed > STILL_MS or (GetVehicleClass(r.veh) ~= 14 and IsEntityInAir(r.veh))) then return end
    goAway(ped, idle)
end

--- The look, once a second while AFK is on and a character is loaded. One loop however often it is asked for.
local function startPolling()
    if polling or not enabled() then return end
    polling = true
    lastInput, last = GetGameTimer(), nil
    CreateThread(function()
        while enabled() and loaded() do
            local cost = WhipCost.start()
            look()
            WhipCost.stop('afk: watching for input (1 a second)', cost)
            Wait(POLL_MS)
        end
        polling = false
        back()
    end)
end

AddEventHandler('whip_core:player:loaded', startPolling)
AddEventHandler('whip_core:player:spawned', startPolling)
AddEventHandler('whip_core:player:logout', function() back() end)
Whip.register(function() if loaded() then startPolling() end end)

-- Turned on or off in /whip → Settings. Off: back at once. The camera off: one up now ends (they are still away).
Whip.onConfigChanged('Enabled', function()
    if enabled() then startPolling() else back() end
end)
Whip.onConfigChanged('Showroom', function(on)
    if on == false then Showroom.stop() end
end)
Whip.onConfigChanged('Ghost', function(on)
    if away then ghost(on == true, GetVehiclePedIsIn(PlayerPedId(), false)) end
end)
AfkPrefs.onChange('showroom', function(on)
    if on == false then Showroom.stop() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if away then
        ghost(false)
        Idle.stop()
    end
end)

-- For client/idle.lua: another player away within its talking distance, on foot as we are, or nil.
Idle.partner = function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return nil end
    local me = GetEntityCoords(ped)
    for id in pairs(Tags.away()) do
        local p = GetPlayerFromServerId(id)
        local other = p ~= -1 and GetPlayerPed(p) or 0
        if other ~= 0 and DoesEntityExist(other) and not IsPedInAnyVehicle(other, false)
            and #(GetEntityCoords(other) - me) <= 2.5 then
            return other
        end
    end
    return nil
end
