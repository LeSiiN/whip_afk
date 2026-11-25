-- ============================================
-- IDLE — what a player away does meanwhile (client)
-- ============================================
--
-- client/main.lua calls Idle.start (on foot) or Idle.startInVehicle when a player is away, and Idle.stop when
-- they are back. On foot it looks at where they stand and picks what fits, in this order:
--
--   a talk     another player away stands within TALK_M: they turn to each other and talk with their hands, so to
--              everyone else it looks like a conversation (each game turns its own player)
--   the couch  at home (a property they own or hold a key to: exports.whip_core:GetCurrentProperty): a sofa, an
--              armchair or a chair (a model from whip's furniture catalogue, COUCH_MODELS) within COUCH_M, in sight.
--              Which side is the seat is read off the piece itself: two rays from above, and the lower one lands on
--              the seat, the higher one on the back rest. They are sat facing away from the back rest, with a couch
--              animation of our own (whip's PlayEmote has no "at this spot")
--   a seat     one of GTA's own seats close by (a bench, a chair, a bar stool, a sun lounger: the world's scenario
--              points): they sit down on it, as the game's people do (warped onto it, the game's own alignment)
--   a wall     right behind them: they lean back on it
--   a rail     at waist height in front of them, nothing above it: they lean on it
--   the ground sand by day in the dry: they sunbathe or sit in it; grass: they sit in it
--   standing   indoors a phone, a coffee, thinking, folded arms; outdoors a cigarette and a map too; in the rain only
--              folded arms or the phone
--
-- In a vehicle (startInVehicle): an arm on the window sill, nodding along to the radio, slumped back. Upper body only,
-- so the legs stay in the seat; the driver's side and the passenger's have their own takes.
--
-- Everything on foot but the seats is one of whip's emotes (exports.whip_core:PlayEmote), played as the player would:
-- others see it, its props are whip's. Never over an emote of their own, nor when emotes are refused (a weapon out,
-- escorted, ...): another is tried, then none. The male and female versions of a pose go to the ped they fit.
--
-- IT KEEPS GOING. A pose that stops by itself (bumped, a scenario that gave up) is started again within KEEP_MS.
-- Standing poses, talking and the car's change to another that fits every ROTATE_MS or so (talking sooner): in the
-- showroom's fade through black when the camera is up (Showroom.onDip), else on the clock. A seat, the couch, a
-- lean or sitting on the ground is kept: people sit still.
--
-- AND ENDS PROPERLY. Idle.stop ends the pose the way the game ends it (standing up from the bench, putting the
-- phone away, the arm coming in off the sill) and answers a check that says when that is over: client/main.lua holds
-- the player's movement until then, so they get up before they walk off.

Idle = {}

local ROTATE_MS      = 40000  -- a standing pose this long at least before the next
local ROTATE_TALK_MS = 15000  -- a talking gesture
local KEEP_MS        = 3000   -- a look this often: a pose that stopped is started again; on its own clock, a change
local SEAT_RADIUS    = 2.5    -- metres: a GTA seat this close is one to sit on
local SEAT_CHECK     = 900    -- ms: then we look whether the game really sat them down
local COUCH_M        = 5.0    -- metres: a couch at home this close is one to sit on
local TALK_M         = 2.5    -- metres: another player away this close is one to talk to
local WALL_M         = 0.6    -- a wall this close behind them is one to lean on
local RAIL_M         = 0.7    -- a rail this close in front of them is one to lean on
local DIP_BLACK      = 720    -- ms after a fade starts that the picture is black (css/afk.css)
local EXIT_CAP_MS    = 4000   -- an exit is over by this, whatever the game says

--- How long each kind's ending takes at least (standing up, the phone away), before the game's word counts.
local EXIT_MS = { seat = 1800, couch = 1400, lean = 1100, rail = 900, sand = 1500, grass = 1500, car = 800 }
local EXIT_DEFAULT = 900

--- GTA's seat scenarios: a point of one of these is somewhere to sit.
local SEATS = {
    'PROP_HUMAN_SEAT_BENCH', 'PROP_HUMAN_SEAT_CHAIR', 'PROP_HUMAN_SEAT_CHAIR_UPRIGHT', 'PROP_HUMAN_SEAT_ARMCHAIR',
    'PROP_HUMAN_SEAT_BAR', 'PROP_HUMAN_SEAT_DECKCHAIR', 'PROP_HUMAN_SEAT_SUNLOUNGER', 'PROP_HUMAN_SEAT_CHAIR_FOOD',
    'PROP_HUMAN_SEAT_BENCH_FACILITY', 'PROP_HUMAN_SEAT_COMPUTER',
}

--- Furniture at home that is somewhere to sit: the seats of whip's furniture catalogue (whip_core's
--- server/prop_catalog_seed.lua), as model hashes once.
local COUCH_MODELS = {
    'apa_mp_h_din_chair_04', 'apa_mp_h_din_chair_08', 'apa_mp_h_din_chair_09', 'apa_mp_h_din_chair_12',
    'apa_mp_h_stn_chairarm_01', 'apa_mp_h_stn_chairarm_02', 'apa_mp_h_stn_chairarm_03', 'apa_mp_h_stn_chairarm_09',
    'apa_mp_h_stn_chairarm_11', 'apa_mp_h_stn_chairarm_12', 'apa_mp_h_stn_chairarm_13', 'apa_mp_h_stn_chairarm_23',
    'apa_mp_h_stn_chairarm_24', 'apa_mp_h_stn_chairarm_25', 'apa_mp_h_stn_chairarm_26', 'apa_mp_h_stn_chairstrip_01',
    'apa_mp_h_stn_chairstrip_03', 'apa_mp_h_stn_chairstrip_05', 'apa_mp_h_stn_chairstrip_07',
    'apa_mp_h_stn_sofa2seat_02', 'apa_mp_h_stn_sofa_daybed_01', 'apa_mp_h_stn_sofa_daybed_02',
    'apa_mp_h_stn_sofacorn_01', 'apa_mp_h_stn_sofacorn_05', 'apa_mp_h_stn_sofacorn_06', 'apa_mp_h_stn_sofacorn_07',
    'apa_mp_h_stn_sofacorn_08', 'apa_mp_h_stn_sofacorn_09', 'apa_mp_h_stn_sofacorn_10', 'apa_mp_h_yacht_armchair_01',
    'apa_mp_h_yacht_armchair_03', 'apa_mp_h_yacht_armchair_04', 'apa_mp_h_yacht_sofa_01', 'apa_mp_h_yacht_sofa_02',
    'ba_prop_battle_club_chair_01', 'ba_prop_battle_club_chair_02', 'ba_prop_battle_club_chair_03',
    'bkr_prop_clubhouse_armchair_01a', 'bkr_prop_clubhouse_offchair_01a', 'bkr_prop_clubhouse_sofa_01a',
    'ex_mp_h_off_easychair_01', 'ex_mp_h_off_sofa_003', 'ex_mp_h_off_sofa_01', 'ex_mp_h_off_sofa_02',
    'ex_prop_offchair_exec_01', 'ex_prop_offchair_exec_02', 'ex_prop_offchair_exec_03', 'ex_prop_offchair_exec_04',
    'gr_prop_gr_offchair_01a', 'gr_prop_highendchair_gr_01a', 'h4_prop_h4_couch_01a', 'hei_heist_din_chair_01',
    'hei_heist_din_chair_02', 'hei_heist_din_chair_03', 'hei_heist_din_chair_04', 'hei_heist_din_chair_05',
    'hei_heist_din_chair_06', 'hei_heist_stn_chairarm_01', 'hei_heist_stn_chairarm_03', 'hei_heist_stn_chairarm_04',
    'hei_heist_stn_chairarm_06', 'hei_heist_stn_sofa2seat_02', 'hei_heist_stn_sofa2seat_03',
    'hei_heist_stn_sofa2seat_06', 'hei_heist_stn_sofa3seat_01', 'hei_heist_stn_sofa3seat_02',
    'hei_heist_stn_sofa3seat_06', 'hei_heist_stn_sofacorn_05', 'hei_heist_stn_sofacorn_06',
    'imp_prop_impexp_offchair_01a', 'imp_prop_impexp_sofabed_01a', 'm24_1_prop_m41_officechair_01a',
    'm24_1_prop_m41_sofa_01a', 'prop_armchair_01', 'prop_chair_01a', 'prop_chair_01b', 'prop_chair_02',
    'prop_chair_03', 'prop_chair_04a', 'prop_chair_05', 'prop_chair_06', 'prop_chair_07', 'prop_chair_08',
    'prop_chair_09', 'prop_chair_10', 'prop_chateau_chair_01', 'prop_couch_01', 'prop_couch_03', 'prop_couch_04',
    'prop_couch_lg_02', 'prop_couch_lg_05', 'prop_couch_lg_06', 'prop_couch_lg_07', 'prop_couch_lg_08',
    'prop_couch_sm_02', 'prop_couch_sm_05', 'prop_couch_sm_06', 'prop_couch_sm_07', 'prop_cs_folding_chair_01',
    'prop_cs_office_chair', 'prop_direct_chair_01', 'prop_ld_farm_couch01', 'prop_ld_farm_couch02',
    'prop_off_chair_01', 'prop_off_chair_03', 'prop_off_chair_04', 'prop_off_chair_05', 'prop_old_deck_chair',
    'prop_old_wood_chair', 'prop_rock_chair_01', 'prop_rub_couch01', 'prop_rub_couch03', 'prop_rub_couch04',
    'prop_t_sofa', 'prop_t_sofa_02', 'sf_prop_sf_offchair_exec_01a', 'sf_prop_sf_offchair_exec_04a',
    'sf_prop_sf_sofa_chefield_01a', 'sf_prop_sf_sofa_chefield_02a', 'sf_prop_sf_sofa_studio_01a',
    'v_club_ch_armchair', 'v_club_officechair', 'v_club_officesofa', 'v_club_vuarmchair', 'v_corp_lazychair',
    'v_corp_offchair', 'v_ilev_m_dinechair', 'v_ilev_m_sofa', 'v_ilev_p_easychair', 'v_med_fabricchair1',
    'v_med_p_deskchair', 'v_med_p_easychair', 'v_med_p_sofa', 'v_med_whickerchair1', 'v_res_d_armchair',
    'v_res_d_sofa', 'v_res_fa_chair01', 'v_res_fa_chair02', 'v_res_fh_easychair', 'v_res_fh_sofa',
    'v_res_j_dinechair', 'v_res_j_sofa', 'v_res_jarmchair', 'v_res_m_armchair', 'v_res_m_dinechair',
    'v_res_m_h_sofa', 'v_res_m_h_sofa_sml', 'v_res_mp_sofa', 'v_res_mp_stripchair', 'v_res_r_sofa',
    'v_res_study_chair', 'v_res_tre_officechair', 'v_res_tre_sofa', 'v_res_tt_sofa', 'vw_prop_vw_offchair_01',
    'vw_prop_vw_offchair_02', 'vw_prop_vw_offchair_03',
}
for i, m in ipairs(COUCH_MODELS) do COUCH_MODELS[i] = GetHashKey(m) end

--- Sitting on it: { dict, clip, 'm' | 'f' | nil }, as whip's sitchair emotes.
local COUCH_POSES = {
    { 'timetable@ron@ig_3_couch', 'base', 'm' },
    { 'timetable@reunited@ig_10', 'base_amanda', 'f' },
    { 'timetable@jimmy@mics3_ig_15@', 'mics3_15_base_tracy' },
    { 'timetable@maid@couch@', 'base' },
}

-- The poses, as whip's emote names; 'm' or 'f' for one made for a man or a woman.
local ARMS = { { 'crossarms', 'f' }, { 'crossarms2', 'm' }, { 'crossarms3' }, { 'foldarms2' } }
local POOLS = {
    talk    = { { 'argue2' }, { 'argue3' }, { 'argue8' }, { 'shrug' }, { 'think3' }, { 'crossarms2', 'm' }, { 'crossarms', 'f' } },
    lean    = { { 'lean' }, { 'lean4', 'm' }, { 'lean2', 'f' }, { 'lean3', 'f' } },
    rail    = { { 'leanbar2' }, { 'leanbar4' } },
    sand    = { { 'sunbathe' }, { 'sit3' }, { 'sit' } },
    grass   = { { 'sit3' }, { 'sit' }, { 'sit2' } },
    indoors = { { 'texting' }, { 'phone' }, { 'coffee' }, { 'think3' }, { 'idle', 'm' }, { 'idle2', 'f' }, table.unpack(ARMS) },
    rain    = { { 'texting' }, table.unpack(ARMS) },
    night   = { { 'texting' }, { 'smoke' }, { 'phone' }, { 'idle', 'm' }, { 'idle2', 'f' }, table.unpack(ARMS) },
    day     = { { 'texting' }, { 'phone' }, { 'coffee' }, { 'smoke' }, { 'map' }, { 'stretch' }, { 'think3' },
                { 'idle', 'm' }, { 'idle2', 'f' }, table.unpack(ARMS) },
}
--- The kinds that change while away (the rest are kept), and how often.
local CHANGING = { indoors = ROTATE_MS, rain = ROTATE_MS, night = ROTATE_MS, day = ROTATE_MS, talk = ROTATE_TALK_MS,
                   car = ROTATE_MS }

--- In a vehicle: { dict, clip }, '%s' the side ('ds' the driver's, 'ps' a passenger's). Ones the game does not have
--- are left out as it is asked (DoesAnimDictExist).
local CAR_POSES = {
    { 'anim@veh@lowrider@std@%s@arm@base', 'sit' },                 -- an arm on the window sill
    { 'anim@veh@lowrider@std@%s@arm@music@hiphop', 'idle_a' },      -- nodding along to the radio
    { 'anim@veh@lowrider@std@%s@arm@music@rock', 'idle_a' },
    { 'amb@code_human_in_car_idles@generic@%s@base', 'base' },      -- slumped back
    { 'amb@code_human_in_car_idles@low@%s@base', 'base' },
}

-- The ground they stand on, by GTA's material names.
local SAND, GRASS = {}, {}
for _, m in ipairs({ 'SAND_LOOSE', 'SAND_COMPACT', 'SAND_WET', 'SAND_TRACK', 'SAND_DRY_DEEP', 'SAND_WET_DEEP' }) do SAND[GetHashKey(m)] = true end
for _, m in ipairs({ 'GRASS', 'GRASS_LONG', 'GRASS_SHORT' }) do GRASS[GetHashKey(m)] = true end

--- Set by client/main.lua: another player away within TALK_M on foot, as their ped, or nil.
---@type function|nil
Idle.partner = nil

---@type table|nil
local now = nil   -- { kind, cmd (an emote of ours) | anim = { dict, clip } (in a vehicle), at (couch spot), changedAt }
local session = 0 -- bumped at each start and stop: a clock or a check from an earlier one stands down

-- ---- looking round ----

local function hit(probe)
    local _, h = GetShapeTestResult(probe)
    return h == 1 or h == true
end

--- A ray from a point on the ped to another (offsets in its own metres), against the world and objects.
local function blocked(ped, a, b)
    local p = GetOffsetFromEntityInWorldCoords(ped, a[1], a[2], a[3])
    local q = GetOffsetFromEntityInWorldCoords(ped, b[1], b[2], b[3])
    return hit(StartExpensiveSynchronousShapeTestLosProbe(p.x, p.y, p.z, q.x, q.y, q.z, 1 + 16, ped, 7))
end

local function groundMaterial(ped)
    local p = GetEntityCoords(ped)
    local probe = StartExpensiveSynchronousShapeTestLosProbe(p.x, p.y, p.z, p.x, p.y, p.z - 2.5, 1, ped, 7)
    local _, h, _, _, material = GetShapeTestResultIncludingMaterial(probe)
    return (h == 1 or h == true) and material or nil
end

local function seatNear(p)
    for _, s in ipairs(SEATS) do
        if DoesScenarioOfTypeExistInArea(p.x, p.y, p.z, s, SEAT_RADIUS, true) then return true end
    end
    return false
end

local function onSeat(ped)
    for _, s in ipairs(SEATS) do
        if IsPedUsingScenario(ped, s) then return true end
    end
    return false
end

local function headingTo(from, to)
    return (math.deg(math.atan(-(to.x - from.x), to.y - from.y)) + 360.0) % 360.0
end

--- Where to sit on this piece of furniture: the seat side found by two rays from above (the lower hit is the seat),
--- in front of its middle, the root a standing height over the floor, facing away from the back rest. nil when the
--- rays find no clear seat.
local function couchSpot(obj, floorZ)
    local mn, mx = GetModelDimensions(GetEntityModel(obj))
    -- The depth is the shorter of its two sides: its own y, or its own x for a piece turned in its model.
    local alongY = (mx.y - mn.y) <= (mx.x - mn.x)
    local depth = alongY and (mx.y - mn.y) or (mx.x - mn.x)
    local top = mx.z + 0.3
    local function landAt(sign)
        local o = depth * 0.3 * sign
        local p = GetOffsetFromEntityInWorldCoords(obj, alongY and 0.0 or o, alongY and o or 0.0, top)
        local probe = StartExpensiveSynchronousShapeTestLosProbe(p.x, p.y, p.z, p.x, p.y, p.z - (mx.z - mn.z) - 0.6, 16, 0, 7)
        local _, h, at = GetShapeTestResult(probe)
        return (h == 1 or h == true) and at.z or nil
    end
    local plus, minus = landAt(1), landAt(-1)
    if not plus or not minus or math.abs(plus - minus) < 0.15 then return nil end
    local sign = plus < minus and 1 or -1
    local o = depth * 0.2 * sign
    local front = GetOffsetFromEntityInWorldCoords(obj, alongY and 0.0 or o * 2.5, alongY and o * 2.5 or 0.0, 0.0)
    local seat = GetOffsetFromEntityInWorldCoords(obj, alongY and 0.0 or o, alongY and o or 0.0, 0.0)
    return { x = seat.x, y = seat.y, z = floorZ + 1.0, heading = headingTo(seat, front) }
end

--- A couch at home in reach and in sight, as a spot to sit on, or nil.
local function couchNear(ped)
    local prop = exports.whip_core:GetCurrentProperty()
    if not prop or not (prop.mine or prop.key) then return nil end
    local me = GetEntityCoords(ped)
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local best, bestD = nil, COUCH_M
    for _, hash in ipairs(COUCH_MODELS) do
        local obj = GetClosestObjectOfType(me.x, me.y, me.z, COUCH_M, hash, false, false, false)
        if obj ~= 0 then
            local d = #(GetEntityCoords(obj) - me)
            if d < bestD then
                local spot = couchSpot(obj, me.z - 1.0)
                if spot then
                    local probe = StartExpensiveSynchronousShapeTestLosProbe(head.x, head.y, head.z, spot.x, spot.y, spot.z, 1, ped, 7)
                    if not hit(probe) then best, bestD = spot, d end
                end
            end
        end
    end
    return best
end

--- Which pool fits where they stand (not the seats: those are tried first, apart).
local function poolFor(ped)
    if Idle.partner and Idle.partner() then return 'talk' end
    if blocked(ped, { 0.0, 0.0, 0.2 }, { 0.0, -WALL_M, 0.2 }) then return 'lean' end
    if blocked(ped, { 0.0, 0.0, 0.05 }, { 0.0, RAIL_M, 0.05 }) and not blocked(ped, { 0.0, 0.0, 0.6 }, { 0.0, RAIL_M + 0.3, 0.6 }) then
        return 'rail'
    end
    local indoors = GetInteriorFromEntity(ped) ~= 0
    local wet = GetRainLevel() > 0.2
    local h = GetClockHours()
    local day = h >= 7 and h < 19
    if not indoors and not wet and day then
        local m = groundMaterial(ped)
        if m and SAND[m] then return 'sand' end
        if m and GRASS[m] then return 'grass' end
    end
    if indoors then return 'indoors' end
    if wet then return 'rain' end
    return day and 'day' or 'night'
end

-- ---- playing ----

--- The emote the player is doing (whip's), or nil.
local function emoting()
    local e = exports.whip_core:IsEmoting()
    return e ~= false and e or nil
end

local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

--- The poses of the pool that fit this ped, other than `except`, in a random order.
local function options(pool, ped, except)
    local male = IsPedMale(ped)
    local out = {}
    for _, e in ipairs(POOLS[pool] or {}) do
        local sex = e[2]
        if e[1] ~= except and (sex == nil or (sex == 'm') == male) then out[#out + 1] = e[1] end
    end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

--- One of the pool's poses, through whip's emotes: the first it accepts (one it does not have, or refuses, is passed).
local function playPool(pool, ped, except)
    for i, cmd in ipairs(options(pool, ped, except)) do
        if i > 4 then break end
        if exports.whip_core:PlayEmote(cmd) then
            now = { kind = pool, cmd = cmd, changedAt = GetGameTimer() }
            return true
        end
    end
    return false
end

--- Sat on the couch at `spot`: put there, facing away from its back rest, in a couch pose that fits the ped.
local function playCouch(ped, spot)
    local male = IsPedMale(ped)
    local fits = {}
    for _, p in ipairs(COUCH_POSES) do
        if p[3] == nil or (p[3] == 'm') == male then fits[#fits + 1] = p end
    end
    local p = fits[math.random(#fits)]
    if not p or not loadDict(p[1]) then return false end
    SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
    SetEntityHeading(ped, spot.heading)
    TaskPlayAnim(ped, p[1], p[2], 8.0, 8.0, -1, 1, 0.0, false, false, false)
    now = { kind = 'couch', anim = { p[1], p[2] }, at = spot, changedAt = GetGameTimer() }
    return true
end

--- Talking: turned to face them first (a turn, not a snap), the gesture once the turn is done.
local function startTalk(ped, partner, except)
    local my = session
    TaskAchieveHeading(ped, headingTo(GetEntityCoords(ped), GetEntityCoords(partner)), 1000)
    now = { kind = 'talk', changedAt = GetGameTimer() }
    SetTimeout(1000, function()
        if session ~= my then return end
        if not playPool('talk', PlayerPedId(), except) then now = { kind = 'talk', changedAt = GetGameTimer() } end
    end)
end

--- In a vehicle: the poses this seat's side has.
local function carPoses(ped, veh)
    local side = GetPedInVehicleSeat(veh, -1) == ped and 'ds' or 'ps'
    local out = {}
    for _, p in ipairs(CAR_POSES) do
        local dict = p[1]:format(side)
        if DoesAnimDictExist(dict) then out[#out + 1] = { dict, p[2] } end
    end
    return out
end

local function playCar(ped, except)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return false end
    local poses = {}
    for _, p in ipairs(carPoses(ped, veh)) do
        if not except or p[1] ~= except[1] then poses[#poses + 1] = p end
    end
    if #poses == 0 then return false end
    local p = poses[math.random(#poses)]
    if not loadDict(p[1]) then return false end
    if except then StopAnimTask(ped, except[1], except[2], 1.0) end
    -- 49: loops, upper body only, and the seat keeps the legs.
    TaskPlayAnim(ped, p[1], p[2], 2.0, 2.0, -1, 49, 0.0, false, false, false)
    now = { kind = 'car', anim = p, changedAt = GetGameTimer() }
    return true
end

--- On to another pose of the same kind (in the fade, or on the clock), or back to one that stopped.
local function change(force)
    local n = now
    if not n then return end
    local ped = PlayerPedId()
    if n.kind == 'car' then
        local every = CHANGING.car
        if force or GetGameTimer() - n.changedAt >= every then
            CreateThread(function() if now == n then playCar(ped, n.anim) end end)
        end
        return
    end
    -- A partner turned up, or went: from standing to talking, or from talking back to standing.
    local partner = Idle.partner and Idle.partner()
    if n.kind == 'talk' and not partner then
        if n.cmd and emoting() == n.cmd then exports.whip_core:CancelEmote() end
        playPool(poolFor(ped), ped)
        return
    end
    if partner and CHANGING[n.kind] and n.kind ~= 'talk' then
        if n.cmd and emoting() == n.cmd then exports.whip_core:CancelEmote() end
        startTalk(ped, partner)
        return
    end
    local every = CHANGING[n.kind]
    if not every then return end
    if not force and GetGameTimer() - n.changedAt < every then return end
    if n.cmd and emoting() ~= n.cmd then return end   -- not ours any more
    playPool(n.kind, ped, n.cmd)
end

--- Every KEEP_MS while away: a pose that stopped by itself starts again; without the camera, the change on the clock.
local function keep(my)
    CreateThread(function()
        while session == my do
            Wait(KEEP_MS)
            if session ~= my then return end
            local n = now
            local ped = PlayerPedId()
            if n then
                if n.kind == 'car' then
                    if n.anim and not IsEntityPlayingAnim(ped, n.anim[1], n.anim[2], 3) then
                        TaskPlayAnim(ped, n.anim[1], n.anim[2], 2.0, 2.0, -1, 49, 0.0, false, false, false)
                    end
                elseif n.kind == 'seat' then
                    -- The game stood them up: sat down again, as long as there is still a seat.
                    if not IsPedUsingAnyScenario(ped) then
                        local p = GetEntityCoords(ped)
                        TaskUseNearestScenarioToCoordWarp(ped, p.x, p.y, p.z, SEAT_RADIUS, 0)
                    end
                elseif n.kind == 'couch' then
                    if n.anim and not IsEntityPlayingAnim(ped, n.anim[1], n.anim[2], 3) then
                        TaskPlayAnim(ped, n.anim[1], n.anim[2], 8.0, 8.0, -1, 1, 0.0, false, false, false)
                    end
                elseif n.cmd and not emoting() then
                    -- Ours stopped and nothing else plays: the same again.
                    if exports.whip_core:PlayEmote(n.cmd) then n.changedAt = GetGameTimer() end
                end
            end
            if not Showroom.active() then change() end
        end
    end)
end

-- ---- the surface ----

--- Start what fits, on foot. Answers how long it needs to settle before a camera looks (ms; 0 when nothing started).
---@param ped integer
---@return integer settleMs
function Idle.start(ped)
    Idle.stop()
    if emoting() then return 0 end
    session = session + 1
    local my = session
    keep(my)

    local partner = Idle.partner and Idle.partner()
    if partner then
        startTalk(ped, partner)
        return 1800
    end

    local spot = couchNear(ped)
    if spot and playCouch(ped, spot) then return 1800 end

    local p = GetEntityCoords(ped)
    if seatNear(p) then
        TaskUseNearestScenarioToCoordWarp(ped, p.x, p.y, p.z, SEAT_RADIUS, 0)
        now = { kind = 'seat', changedAt = GetGameTimer() }
        SetTimeout(SEAT_CHECK, function()
            if session ~= my then return end
            local me = PlayerPedId()
            if onSeat(me) then return end
            ClearPedTasks(me)
            now = nil
            playPool(poolFor(me), me)
        end)
        return SEAT_CHECK + 1300
    end

    if not playPool(poolFor(ped), ped) then
        session = session + 1
        return 0
    end
    return 1500
end

--- Start a pose in the vehicle they sit in. Not on a bike, a boat or an aircraft (no seat to lean in).
---@param ped integer
---@param veh integer
function Idle.startInVehicle(ped, veh)
    Idle.stop()
    local class = GetVehicleClass(veh)
    if class == 8 or class == 13 or class == 14 or class == 15 or class == 16 then return end
    session = session + 1
    local my = session
    keep(my)
    CreateThread(function()
        if session == my and not playCar(ped) then session = session + 1 end
    end)
end

--- They are back: the pose ends the way the game ends it. Answers a check that is true once that is over (the
--- player gets up before they move on), or nil when nothing was playing.
---@return function|nil done
function Idle.stop()
    local n = now
    now = nil
    session = session + 1
    if not n then return nil end
    local ped = PlayerPedId()
    if n.kind == 'seat' then
        if IsPedUsingAnyScenario(ped) then ClearPedTasks(ped) end
    elseif n.kind == 'car' or n.kind == 'couch' then
        if n.anim then
            StopAnimTask(ped, n.anim[1], n.anim[2], 1.0)
            RemoveAnimDict(n.anim[1])
        end
    elseif n.cmd and emoting() == n.cmd then
        exports.whip_core:CancelEmote()
    end
    local started = GetGameTimer()
    local least = EXIT_MS[n.kind] or EXIT_DEFAULT
    return function()
        local age = GetGameTimer() - started
        if age >= EXIT_CAP_MS then return true end
        if age < least then return false end
        local me = PlayerPedId()
        if IsPedUsingAnyScenario(me) then return false end
        if n.anim and IsEntityPlayingAnim(me, n.anim[1], n.anim[2], 3) then return false end
        return true
    end
end

-- The showroom's fades: a changing pose changes while the picture is black.
Showroom.onDip = function()
    if not now then return end
    SetTimeout(DIP_BLACK, function() change() end)
end
