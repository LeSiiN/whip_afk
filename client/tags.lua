-- ============================================
-- TAGS — "AFK · 3 min" over the heads of others who are away (client)
-- ============================================
--
-- Every game reads every player's whip_afk bag (server/main.lua: os.time() at their last input). While anyone is
-- away a slow look (once a second) gives each one near enough (Config.BubbleRange) a tag, and says how long. The
-- tag is a capsule in the look of whip's /me bubbles: one browser (whip_core's DuiPage, html/tag.html) paints every
-- tag into its own cell of one texture, and each cell is drawn as a camera-facing quad (whip_core's WorldQuad)
-- above that player's head, so it is hidden behind walls like the world is. Drawn every frame only while at least
-- one tag is up; nothing runs while nobody near is away.

Tags = {}

local KEY = 'whip_afk'
local CELL_W, CELL_H, CELLS, STALK_PX = 768, 256, 6, 64
local MPP = 0.0026          -- metres per texel: whip's /me bubbles' size
local HEIGHT = 0.3          -- metres over the head
local HEAD_BONE = 31086
local FOLD_MS = 700         -- the page's fold, with margin, before a cell is free again
local TXD, TEX = 'whip_afk_tags', 'tags'

-- whip's clean screen (filming): while it hides the world's things, WorldQuad draws nothing (it reads this table).
CleanScreen = { world = false }
AddEventHandler('whip_core:ui:cleanScreen', function(e)
    CleanScreen.world = type(e) == 'table' and e.world == true
end)

local page = DuiPage.new({
    name = 'afk tags',
    url = ('tag.html?w=%d&h=%d&cells=%d&stalk=%d'):format(CELL_W, CELL_H, CELLS, STALK_PX),
    width = CELL_W, height = CELL_H * CELLS, txd = TXD, tex = TEX,
    idleMs = 60000, without = 'AFK tags will not draw',
})

local away = {}       -- [serverId] = os.time() at their last input
local shown = {}      -- [serverId] = { cell, text, long, freeAt (folding) }
local cellOf = {}     -- [cell] = serverId
local watching, drawing = false, false

local function myServerId() return GetPlayerServerId(PlayerId()) end

--- Seconds now on the same clock as the bag (POSIX). The cloud's time, which is the real time on every game.
local function nowSeconds()
    local t = GetCloudTimeAsInt()
    return (t and t > 0) and t or nil
end

local function tagText(since)
    local t = nowSeconds()
    if not t then return 'AFK' end
    local mins = math.floor(math.max(0, t - since) / 60)
    if mins < 1 then return 'AFK' end
    return ('AFK · %d min'):format(mins)
end

local function pedOf(id)
    local p = GetPlayerFromServerId(id)
    if p == -1 then return 0 end
    return GetPlayerPed(p)
end

local function freeCell()
    for i = 1, CELLS do
        if not cellOf[i] then return i end
    end
    return nil
end

local function hide(id)
    local s = shown[id]
    if not s or s.freeAt then return end
    page:send({ cell = s.cell - 1, hide = true })
    s.freeAt = GetGameTimer() + FOLD_MS
end

--- Every frame while any tag is up (or folding).
local function draw()
    drawing = true
    CreateThread(function()
        while next(shown) do
            local now = GetGameTimer()
            local cost = WhipCost.start()
            local rx, ry, rz, ux, uy, uz = WorldQuad.billboardBasis()
            local w, h = CELL_W * MPP, CELL_H * MPP
            for id, s in pairs(shown) do
                if s.freeAt and now >= s.freeAt then
                    shown[id], cellOf[s.cell] = nil, nil
                elseif page:up() then
                    page:used()
                    local ped = pedOf(id)
                    if ped ~= 0 and DoesEntityExist(ped) and IsEntityVisible(ped) then
                        local head = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
                        local ax, ay, az = head.x, head.y, head.z + HEIGHT
                        local half = h * 0.5
                        WorldQuad.draw(TXD, TEX, ax + ux * half, ay + uy * half, az + uz * half,
                            rx, ry, rz, ux, uy, uz, w, h,
                            0.0, (s.cell - 1) / CELLS, 1.0, s.cell / CELLS, 255, 255, 255, 255)
                    end
                end
            end
            WhipCost.stop('afk: tags over players away (every frame while one is up)', cost)
            Wait(0)
        end
        drawing = false
    end)
end

--- Once a second while anyone is away: a tag over each one near enough, and how long; off the rest.
local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        while next(away) or next(shown) do
            local cost = WhipCost.start()
            local me = GetEntityCoords(PlayerPedId())
            local range = tonumber(Config.BubbleRange) or 20.0
            local on = Config.Enabled ~= false and Config.Bubble ~= false
            for id, since in pairs(away) do
                local ped = pedOf(id)
                local near = on and ped ~= 0 and DoesEntityExist(ped) and #(GetEntityCoords(ped) - me) <= range
                local s = shown[id]
                if near then
                    local text = tagText(since)
                    local long = IsPedInAnyVehicle(ped, false)
                    if s and s.freeAt then s = nil end
                    if not s then
                        local cell = freeCell()
                        if cell and page:ensure() then
                            s = { cell = cell }
                            shown[id], cellOf[cell] = s, id
                        end
                    end
                    if s and (s.text ~= text or s.long ~= long) then
                        page:send({ cell = s.cell - 1, long = long, text = text })
                        s.text, s.long = text, long
                    end
                    if s and not drawing then draw() end
                else
                    hide(id)
                    -- Out of this game's reach and no longer away (a change it never heard): forgotten.
                    if ped == 0 and Player(id).state[KEY] == nil then away[id] = nil end
                end
            end
            for id in pairs(shown) do
                if not away[id] then hide(id) end
            end
            WhipCost.stop('afk: tags, who is near (1 a second)', cost)
            Wait(1000)
        end
        watching = false
    end)
end

--- For client/idle.lua's talk: the players away, by server id.
function Tags.away() return away end

local function setAway(id, since)
    if id == myServerId() then return end
    if type(since) == 'number' then
        away[id] = since
        watch()
    elseif away[id] then
        away[id] = nil
        hide(id)
    end
end

AddStateBagChangeHandler(KEY, nil, function(bagName, _, value)
    local id = tonumber(bagName:match('^player:(%d+)$'))
    if id then setAway(id, value) end
end)

-- Whoever was away before this game (or this resource) started.
CreateThread(function()
    for _, p in ipairs(GetActivePlayers()) do
        local id = GetPlayerServerId(p)
        local since = Player(id).state[KEY]
        if since ~= nil then setAway(id, since) end
    end
end)
