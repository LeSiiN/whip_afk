-- ============================================
-- Each player's own choices (client)
-- ============================================
--
-- Rows on the pause menu's Settings → Server page (Whip.playerSetting), group AFK. The values live on this PC, in this
-- resource's KVP; only a choice that differs from the default is kept, so a player who never chose follows the
-- server's config (the delay's default is Config.Delay, which an admin may change later).
--
--     AfkPrefs.get('showroom')   true / false
--     AfkPrefs.get('emote')      true / false
--     AfkPrefs.get('delay')      seconds

AfkPrefs = {}

local KVP = 'whip_afk:prefs'

local function delayDefault() return math.max(15, math.min(600, math.floor(tonumber(Config.Delay) or 60))) end

local DEFAULTS = {
    showroom = function() return true end,
    emote    = function() return true end,
    delay    = delayDefault,
}

local chosen = {}
do
    local raw = GetResourceKvpString(KVP)
    local ok, data = pcall(json.decode, raw or '')
    if ok and type(data) == 'table' then
        for k, v in pairs(data) do if DEFAULTS[k] then chosen[k] = v end end
    end
end

local function save()
    if next(chosen) == nil then DeleteResourceKvp(KVP) return end
    SetResourceKvp(KVP, json.encode(chosen))
end

--- The value in force: the player's choice, else the default.
function AfkPrefs.get(key)
    local v = chosen[key]
    if v == nil and DEFAULTS[key] then v = DEFAULTS[key]() end
    return v
end

local hooks = {}

--- fn(value) after the player changes `key`.
function AfkPrefs.onChange(key, fn)
    hooks[key] = hooks[key] or {}
    hooks[key][#hooks[key] + 1] = fn
end

local function choose(key, value)
    if value == DEFAULTS[key]() then chosen[key] = nil else chosen[key] = value end
    save()
    for _, fn in ipairs(hooks[key] or {}) do pcall(fn, AfkPrefs.get(key)) end
end

local function enabled() return Config.Enabled ~= false end

Whip.playerSetting({
    key = 'afk.showroom', group = 'AFK', type = 'toggle', label = 'Cinematic camera while away',
    help = 'When you are away, standing or in a vehicle that stands still, the camera shows you or the vehicle off with slow shots. Any key brings you back.',
    default = true,
    visible = function() return enabled() and Config.Showroom ~= false end,
    get = function() return AfkPrefs.get('showroom') end,
    set = function(v) choose('showroom', v == true) end,
})

Whip.playerSetting({
    key = 'afk.emote', group = 'AFK', type = 'toggle', label = 'Idle animation while away',
    help = 'When you are away, your character does what fits where you are: sits on the couch at home or a bench close by, leans on a wall, sits in the sand, talks with another player who is away, rests an arm on the car window.',
    default = true,
    visible = function() return enabled() and Config.IdleEmotes ~= false end,
    get = function() return AfkPrefs.get('emote') end,
    set = function(v) choose('emote', v == true) end,
})

Whip.playerSetting({
    key = 'afk.delay', group = 'AFK', type = 'slider', label = 'Away after',
    help = 'How long with no input before you are marked away: others see an AFK tag over your head.',
    min = 15, max = 600, step = 15, unit = 's',
    default = delayDefault(),
    visible = enabled,
    get = function() return AfkPrefs.get('delay') end,
    set = function(v)
        v = math.floor(tonumber(v) or delayDefault())
        choose('delay', math.max(15, math.min(600, v)))
    end,
})
