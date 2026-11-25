-- ============================================
-- SHOWROOM — the car shown off while its player is away, or a portrait of them on foot
-- ============================================
--
-- client/main.lua starts it when a player is away, in a stopped vehicle or on foot, and stops it at the first key.
-- It is a camera SEQUENCE played by whip_core's camera (exports.whip_core:PlayCameraSequence), looping, round the
-- vehicle as the subject 'car' or round the player: no camera code of its own. The same maths (whip_core's
-- cam_math, cam_sequence and cam_shots, loaded in our manifest) plays each shot ahead of time for the walls test.
-- On foot it is a portrait: slow shots of the character (whatever client/idle.lua has them do), and the
-- corner shows their name and where they are instead of a make and a plate. On top of it:
--
--   the page    thin bars top and bottom, the make's logo, the model, the plate and how long they have been away
--               (html/afk.js, html/afk.css: our own page, which whip's clean screen does not hide)
--   soft cuts   a slow fade through black over each cut, started from the AFK frame hook ahead of it
--   the HUD     away the whole time (exports.whip_core:HoldCleanScreen), with whip's prompts and bubbles in the world
--   the lights  headlights on while it plays, given back to the driver after (only for the game that drives it);
--               the high beams flash twice in a front shot, the brake lights glow in a tail shot, and at night the
--               cabin light is on while the camera looks in (LIGHT_FX below)
--   the numbers top speed, acceleration, braking and traction as bars against the best of its class (GTA's own
--               figures, upgrades included), in the corner beside the make
--   the film    a soft vignette and a fine grain over the picture (css/afk.css)
--   a guest     another player close by (GUEST_M) gets a shot of their own; one who comes or goes is taken in, or
--               out, at the next fade (the sequence is built again in the black)
--   a photo     one picture of the second shot (exports.whip_core:TakeScreenshot), kept for the "welcome back"
--               card (client/main.lua), without the page
--   the focus   depth of field (`dof` on a shot, 0 to 1): the point the shot looks at sharp, what is nearer and
--               further soft, set each frame from where the camera is, on the camera GTA is rendering (ours). GTA draws it only with its post-processing
--               at High or above; below that the picture is simply sharp
--
-- THE SHOTS (SETS below) are orbits round the vehicle, or round the player for a rider: yaw 0 behind it, 90 on
-- its left, 180 in front; `aim` a share of its box (+x right, +y front, +z top); `fit` a distance that frames the
-- whole vehicle, or `dist` metres, scaled by the vehicle's length against a car's. A shot with `b` glides (or
-- swings round, `move = 'orbit'`) from `a` to `b` over its time, at an even pace (no easing in or out: the camera is
-- already moving as the picture fades up, and still moving as it fades out, which is what makes it calm). Slow on
-- purpose: about a dozen seconds a shot, a degree a second or less; the big moves (the drone, the crane) take
-- longer still and travel less. Which shots, by what the vehicle is and the
-- moment: at night the lights' shots stand in for the cockpit, in rain a low shot over the wet road joins in and
-- everything goes slower; around sunrise and sunset a low shot looks into the sun, the car or the player against
-- the light (SUN); and a drone rises slowly high over them until the town is in the picture. The order is shuffled, round after round, and each shot picks its side at random (the
-- shots mirrored), so no two runs and no two rounds look the same.
--
-- WALLS. Before it starts, every shot is tried where it stands: from the point it looks at out to the camera (and a
-- little past, for the lens), at its start, middle and end. A shot with a wall, a car or a prop in the way is left
-- out, so a garage or a flat gets only the shots that fit in it; with fewer than two left there is no showroom (the
-- player is still away, with the normal camera).

Showroom = {}

local CLEAN = 'showroom'   -- our HoldCleanScreen id
local CAR_LENGTH = 4.6     -- metres: `dist` is for a car this long, and scaled for anything else
local DIP_LEAD_MS = 820    -- the fade starts this long before a cut; the page is black at the cut (css/afk.css)
local DIP_BLACK_MS = 720   -- ...and black this long after it starts
local IN_MS, OUT_MS = 3000, 500
-- Depth of field: at `dof` 1 sharp from 55% to 150% of the distance to the focus point, at 0 from 25% to 360%
-- (wider and gentler). Its strength from 0.5 to 1 along with it.
local DOF_NEAR, DOF_NEAR_K = 0.25, 0.30
local DOF_FAR, DOF_FAR_K = 3.6, 2.1
-- The walls test: what blocks a shot (the world, vehicles and objects; not people), and how far past the camera
-- must be clear as well.
local RAY_FLAGS, RAY_PAST = 1 + 2 + 16, 0.35
local MIN_SHOTS = 2
local GUEST_M, GUEST_KEEP_M = 12.0, 18.0   -- a guest is someone this close; one already in is kept out to the second
local PHOTO_AT = 4000                      -- ms into the second shot: the photo (not near a fade)
local ROUNDS = 5          -- rounds of the shots, each shuffled, before the whole of it loops (about five minutes)

-- What the lights do in a shot, by its name (only on the game that drives the car):
--   flash   the high beams, on and off at these ms into the shot
--   brake   the brake lights on the whole shot
--   cabin   the cabin light on the whole shot, at night
local FLASH = { { 2500, true }, { 2800, false }, { 3050, true }, { 3350, false } }
local LIGHT_FX = {
    light = { flash = true }, beams = { flash = true }, hero = { flash = true }, blight = { flash = true },
    tail = { brake = true }, btail = { brake = true },
    cockpit = { cabin = true }, cab = { cabin = true }, cabin = { cabin = true },
}

-- Where the sun stands around sunrise and sunset, as a heading (0 north, 90 west, 270 east): GTA's sun comes up
-- in the east-north-east and goes down in the west-north-west. Hours from, to (the last one not included).
local SUN = { { 6, 8, 285.0 }, { 18, 20, 75.0 } }

-- ---- the shots ----

local S = {
    -- A front wheel up close and low, the view creeping up off it onto the body.
    wheel   = { dur = 13000, dof = 1.0, a = { yaw = 150, pitch = -2, aim = { x = -1.0, y = 0.62, z = -0.7 }, dist = 2.2, fov = 32, clear = 0.12 },
                             b = { yaw = 145, pitch = 1, aim = { x = -0.85, y = 0.56, z = -0.4 }, dist = 2.45, fov = 33, clear = 0.12 } },
    -- From behind, three-quarters on, drifting slowly round.
    rear    = { dur = 13000, dof = 0.35, a = { yaw = 30, pitch = 7, fit = 1.08, fov = 40, turn = 1.43 } },
    -- A headlight up close, from the front corner.
    light   = { dur = 11000, dof = 1.0, a = { yaw = 200, pitch = 4, aim = { x = 0.72, y = 1.0, z = 0.15 }, dist = 1.6, fov = 28, turn = -0.65 } },
    -- Through the driver's window (the driver sits on the left: never mirrored).
    cockpit = { dur = 11000, dof = 0.8, side = true, a = { yaw = 98, pitch = 4, aim = { x = -0.2, y = 0.05, z = 0.45 }, dist = 2.0, fov = 36, turn = 0.52 } },
    -- Up over it, swinging round a little as it rises.
    crane   = { dur = 18000, move = 'orbit', a = { yaw = 205, pitch = 10, fit = 1.12, fov = 42 },
                                             b = { yaw = 220, pitch = 28, fit = 1.22, fov = 43 } },
    -- Night: low in front, in the beams, then the tail lights up close.
    beams   = { dur = 12000, dof = 0.5, a = { yaw = 180, pitch = -2, aim = { z = -0.3 }, fit = 1.2, fov = 34, clear = 0.15 },
                             b = { yaw = 175, pitch = 1, aim = { z = -0.15 }, fit = 1.05, fov = 34, clear = 0.15 } },
    tail    = { dur = 11000, dof = 1.0, a = { yaw = -18, pitch = 3, aim = { x = 0.7, y = -1.0, z = 0.25 }, dist = 1.6, fov = 28, turn = 0.65 } },
    -- Rain: along the side, just over the wet road.
    puddle  = { dur = 12000, dof = 0.6, a = { yaw = 62, pitch = -1, aim = { z = -0.45 }, fit = 1.05, fov = 32, clear = 0.08, turn = 0.98 } },
    -- A truck or a bus: head on from low down, big in the frame; the cab, not a car's window.
    hero    = { dur = 12000, dof = 0.5, a = { yaw = 180, pitch = -5, aim = { z = 0.1 }, fit = 1.0, fov = 28, clear = 0.15 },
                             b = { yaw = 172, pitch = -3, aim = { z = 0.15 }, fit = 1.06, fov = 29, clear = 0.15 } },
    cab     = { dur = 11000, dof = 0.8, side = true, a = { yaw = 100, pitch = 6, aim = { x = -0.15, y = 0.7, z = 0.5 }, dist = 2.6, fixed = true, fov = 36, turn = 0.52 } },
    -- A bike: its front wheel, its rider, its headlight and tail.
    bwheel  = { dur = 11000, dof = 1.0, a = { yaw = 165, pitch = -2, aim = { y = 0.85, z = -0.6 }, dist = 1.6, fov = 32, clear = 0.1 },
                             b = { yaw = 157, pitch = 3, aim = { y = 0.6, z = -0.1 }, dist = 2.0, fov = 34, clear = 0.1 } },
    brear   = { dur = 13000, dof = 0.35, a = { yaw = 30, pitch = 8, fit = 1.25, fov = 40, turn = 1.43 } },
    rider   = { dur = 11000, dof = 0.9, a = { subject = 'player', yaw = 150, pitch = 4, aim = { z = 0.55 }, dist = 1.7, fov = 34, turn = 0.65 } },
    blight  = { dur = 10000, dof = 1.0, a = { yaw = 185, pitch = 3, aim = { y = 1.0, z = 0.25 }, dist = 1.4, fov = 30, turn = -0.65 } },
    btail   = { dur = 10000, dof = 1.0, a = { yaw = -8, pitch = 3, aim = { y = -1.0, z = 0.3 }, dist = 1.4, fov = 30, turn = 0.65 } },
    bcrane  = { dur = 18000, move = 'orbit', a = { yaw = 205, pitch = 10, fit = 1.3, fov = 42 },
                                             b = { yaw = 220, pitch = 26, fit = 1.4, fov = 43 } },
    -- A boat: along the waterline, the bow, the helm. `clear` off: the ground under water is the seabed.
    water   = { dur = 12000, dof = 0.5, a = { yaw = 150, pitch = 2, aim = { y = 0.55, z = -0.2 }, fit = 0.95, fov = 34, clear = -1 },
                             b = { yaw = 141, pitch = 4, aim = { y = 0.4, z = -0.05 }, fit = 1.0, fov = 36, clear = -1 } },
    wrear   = { dur = 13000, dof = 0.35, a = { yaw = 35, pitch = 9, fit = 1.15, fov = 40, turn = 1.3, clear = -1 } },
    bow     = { dur = 11000, dof = 0.6, a = { yaw = 180, pitch = 14, aim = { y = 0.9, z = 0.35 }, dist = 3.0, fov = 32, turn = 0.65, clear = -1 } },
    helm    = { dur = 11000, dof = 0.8, side = true, a = { subject = 'player', yaw = 110, pitch = 6, aim = { z = 0.5 }, dist = 2.4, fov = 36, turn = 0.52, clear = -1 } },
    wcrane  = { dur = 18000, move = 'orbit', a = { yaw = 215, pitch = 10, fit = 1.15, fov = 42, clear = -1 },
                                             b = { yaw = 230, pitch = 28, fit = 1.25, fov = 43, clear = -1 } },
    -- A helicopter or a plane: its nose from low, along its side, the cockpit, and high over it.
    nose    = { dur = 12000, dof = 0.5, a = { yaw = 172, pitch = -3, aim = { y = 0.75, z = -0.2 }, fit = 0.65, fov = 34 },
                             b = { yaw = 165, pitch = 2, aim = { y = 0.6, z = -0.05 }, fit = 0.75, fov = 35 } },
    side    = { dur = 13000, dof = 0.35, a = { yaw = 75, pitch = 6, fit = 1.1, fov = 40, turn = 1.43 } },
    cabin   = { dur = 11000, dof = 0.7, side = true, a = { yaw = 125, pitch = 4, aim = { x = -0.2, y = 0.55, z = 0.3 }, fit = 0.45, fov = 36, turn = 0.52 } },
    acrane  = { dur = 18000, move = 'orbit', a = { yaw = 215, pitch = 12, fit = 1.15, fov = 42 },
                                             b = { yaw = 230, pitch = 30, fit = 1.25, fov = 43 } },
    -- Into the sun at sunrise or sunset (`sun`: its yaw is set so the camera looks at the sun, never mirrored).
    golden   = { dur = 13000, dof = 0.5, sun = true, a = { yaw = 0, pitch = 2, aim = { z = 0.1 }, fit = 1.15, fov = 36, turn = 0.52, clear = 0.15 } },
    fgolden  = { dur = 12000, dof = 0.7, sun = true, a = { subject = 'player', yaw = 0, pitch = 3, aim = { z = 0.6 }, dist = 2.4, fov = 34, turn = 0.39 } },
    -- A drone: from behind and above, rising slowly high and far until the town is in the picture.
    drone    = { dur = 22000, a = { yaw = 165, pitch = 22, dist = 10, fixed = true, fov = 46 },
                              b = { yaw = 178, pitch = 42, dist = 28, fixed = true, fov = 50 } },
    fdrone   = { dur = 22000, a = { subject = 'player', yaw = 165, pitch = 18, dist = 6, fov = 46 },
                              b = { subject = 'player', yaw = 178, pitch = 40, dist = 24, fov = 50 } },
    -- A guest: whoever stands close by, in a portrait of their own.
    guest    = { dur = 10000, dof = 0.8, side = true, a = { subject = 'guest', yaw = 160, pitch = 3, aim = { z = 0.7 }, dist = 2.4, fov = 34, turn = 0.52 } },
    -- On foot, round the player: the whole figure, a portrait, from low down, the profile, over the shoulder, and
    -- wide, rising. `dist` in metres, never scaled.
    full     = { dur = 13000, dof = 0.5, a = { subject = 'player', yaw = 200, pitch = 5, aim = { z = 0.1 }, dist = 3.4, fov = 40, turn = 0.78 } },
    portrait = { dur = 12000, dof = 1.0, a = { subject = 'player', yaw = 155, pitch = 1, aim = { z = 0.78 }, dist = 1.25, fov = 30, turn = 0.52 } },
    low      = { dur = 13000, dof = 0.6, a = { subject = 'player', yaw = 140, pitch = -10, aim = { z = 0.45 }, dist = 2.3, fov = 34, clear = 0.2 },
                                         b = { subject = 'player', yaw = 136, pitch = -8, aim = { z = 0.48 }, dist = 2.2, fov = 34, clear = 0.2 } },
    profile  = { dur = 11000, dof = 1.0, a = { subject = 'player', yaw = 92, pitch = 0, aim = { z = 0.75 }, dist = 1.5, fov = 32 },
                                         b = { subject = 'player', yaw = 102, pitch = 1, aim = { z = 0.75 }, dist = 1.45, fov = 32 } },
    shoulder = { dur = 11000, dof = 0.3, a = { subject = 'player', yaw = 25, pitch = 3, aim = { x = 0.3, z = 0.75 }, dist = 1.1, fov = 38, turn = 0.39 } },
    wide     = { dur = 16000, move = 'orbit', a = { subject = 'player', yaw = 220, pitch = 14, aim = { z = 0.3 }, dist = 4.5, fov = 42 },
                                              b = { subject = 'player', yaw = 229, pitch = 22, aim = { z = 0.3 }, dist = 5.2, fov = 43 } },
}

--- The order of the shots, by what the vehicle is: day, and night.
local SETS = {
    car   = { day = { 'wheel', 'rear', 'light', 'cockpit', 'crane', 'drone' },   night = { 'beams', 'rear', 'light', 'tail', 'crane', 'drone' } },
    truck = { day = { 'hero', 'wheel', 'rear', 'cab', 'crane', 'drone' },        night = { 'hero', 'rear', 'light', 'tail', 'crane', 'drone' } },
    bike  = { day = { 'bwheel', 'brear', 'rider', 'blight', 'bcrane', 'drone' }, night = { 'blight', 'brear', 'rider', 'btail', 'bcrane', 'drone' } },
    boat  = { day = { 'water', 'wrear', 'bow', 'helm', 'wcrane', 'drone' },      night = { 'water', 'wrear', 'bow', 'helm', 'wcrane', 'drone' } },
    air   = { day = { 'nose', 'side', 'cabin', 'acrane' },                       night = { 'nose', 'side', 'cabin', 'acrane' } },
    foot  = { day = { 'full', 'portrait', 'low', 'profile', 'shoulder', 'wide', 'fdrone' },
              night = { 'full', 'portrait', 'low', 'profile', 'shoulder', 'wide', 'fdrone' } },
}

--- What the vehicle is, for its shots, and how long it is.
---@return string kind, number length
local function kindOf(veh)
    local model = GetEntityModel(veh)
    local mn, mx = GetModelDimensions(model)
    local len = math.max(mx.y - mn.y, 0.5)
    local class = GetVehicleClass(veh)
    if class == 14 then return 'boat', len end
    if class == 15 or class == 16 then return 'air', len end
    if class == 8 or class == 13 or IsThisModelAQuadbike(model) then return 'bike', len end
    -- Industrial, service (buses) and commercial, or anything as long as a lorry.
    if class == 10 or class == 17 or class == 20 or len > 7.5 then return 'truck', len end
    return 'car', len
end

local function isNight()
    local h = GetClockHours()
    return h >= 20 or h < 6
end

--- The sun's heading around sunrise or sunset, or nil at any other hour.
local function sunHeading()
    local h = GetClockHours()
    for _, w in ipairs(SUN) do
        if h >= w[1] and h < w[2] then return w[3] end
    end
    return nil
end

--- One of our orbits as the sequence takes it: mirrored to the other side (`m` -1), `dist` scaled to the vehicle.
local function orbit(o, m, scale, slow)
    local shot = { kind = 'orbit', subject = o.subject or 'car', yaw = (o.yaw or 0.0) * m, pitch = o.pitch or 8.0,
                   fov = o.fov or 40.0, clear = o.clear }
    if o.turn then shot.turn = o.turn * m * slow end
    if o.aim then shot.aim = { x = (o.aim.x or 0.0) * m, y = o.aim.y or 0.0, z = o.aim.z or 0.0 } end
    if o.fit then
        shot.fit = o.fit
    else
        local s = (o.subject == 'player' or o.subject == 'guest' or o.fixed) and 1.0 or scale
        shot.dist = (o.dist or 4.0) * s
    end
    return shot
end

--- A point on an entity, as a share of its box (a shot's `aim`), in the world.
local function aimPoint(ent, aim)
    local mn, mx = GetModelDimensions(GetEntityModel(ent))
    local right, fwd, up = CamShots.aimLocal({ min = mn, max = mx }, aim)
    return GetOffsetFromEntityInWorldCoords(ent, right, fwd, up)
end

--- Nothing between `from` and `to`, nor RAY_PAST beyond `to`?
local function sightClear(from, to, ignore)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.05 then return true end
    local k = (len + RAY_PAST) / len
    local probe = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z,
        from.x + dx * k, from.y + dy * k, from.z + dz * k, RAY_FLAGS, ignore, 7)
    local _, hit = GetShapeTestResult(probe)
    return not (hit == 1 or hit == true)
end

--- Does this shot (its keys from 0, `dur` long) see its subject at its start, middle and end?
local function shotClear(keys, dur, opt, first)
    local seq = CamSequence.clean({ keys = keys, length = dur })
    if not seq then return false end
    local ent = opt.ents[first.subject]
    if not ent or not DoesEntityExist(ent) then return false end
    local from = aimPoint(ent, first.aim or { x = 0.0, y = 0.0, z = 0.0 })
    local run = CamSequence.newRun(seq, opt.subjects)
    for i, share in ipairs({ 0.02, 0.5, 0.98 }) do
        run.frame = i
        local pose = CamSequence.evaluate(run, dur * share, 1.0)
        if not pose or not sightClear(from, pose, opt.ignore) then return false end
    end
    return true
end

--- One shot on one side (`m` 1, or -1 mirrored), as keys from 0, if nothing is in its way; else false.
local function variant(name, m, opt)
    local sh = S[name]
    local dur = math.floor(sh.dur * opt.stretch)
    local a = sh.a
    if sh.sun then
        -- An orbit looks along its subject's heading plus its yaw: that sum is the sun's heading.
        local sun = sunHeading()
        if not sun then return false end
        local ent = opt.ents[a.subject or 'car']
        a = setmetatable({ yaw = CamMath.wrap180(sun - GetEntityHeading(ent)) }, { __index = sh.a })
    end
    local first = orbit(a, m, opt.scale, opt.slow)
    local own = sh.b
        and { { t = 0, shot = first, move = sh.move or 'glide', ease = 'linear' },
              { t = dur - 1, shot = orbit(sh.b, m, opt.scale, opt.slow), move = 'cut' } }
        or { { t = 0, shot = first, move = 'cut' } }
    if not shotClear(own, dur, opt, first) then return false end
    return { own = own, dur = dur, name = name,
             focus = sh.dof and { dof = sh.dof, subject = first.subject, aim = first.aim or { x = 0.0, y = 0.0, z = 0.0 } } or false }
end

--- `list` in a random order, never starting with `avoid` (the shot just before: no shot twice in a row).
local function shuffled(list, avoid)
    local out = { table.unpack(list) }
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    if #out > 1 and out[1] == avoid then
        local j = math.random(2, #out)
        out[1], out[j] = out[j], out[1]
    end
    return out
end

--- The looping sequence of these shots: ROUNDS rounds of them, each in an order of its own and each shot on a side
--- picked at random, so minutes go by before anything repeats. A shot with a wall in the way on one side may still
--- stand on the other; one with walls on both is left out. Answers the sequence, the times of its cuts (the loop's
--- end is one), each shot's focus and each shot's name, or nil when fewer than MIN_SHOTS can stand.
--- opt: { scale, slow, stretch, subjects, ents ([subject] = entity), ignore (the entity the walls test looks past) }
---@return table|nil seq, integer[] cuts, table focus, string[] names
local function assemble(list, opt)
    local sides, usable = {}, {}
    for _, name in ipairs(list) do
        if not sides[name] then
            local ok = {}
            for _, m in ipairs((S[name].side or S[name].sun) and { 1 } or { 1, -1 }) do
                local v = variant(name, m, opt)
                if v then ok[#ok + 1] = v end
            end
            sides[name] = ok
            if #ok > 0 then usable[#usable + 1] = name end
        end
    end
    if #usable < MIN_SHOTS then return nil end

    local keys, cuts, focus, names, t, prev = {}, {}, {}, {}, 0, nil
    for _ = 1, ROUNDS do
        for _, name in ipairs(shuffled(usable, prev)) do
            local options = sides[name]
            local v = options[math.random(#options)]
            for _, k in ipairs(v.own) do
                keys[#keys + 1] = { t = t + k.t, shot = k.shot, move = k.move, ease = k.ease }
            end
            t = t + v.dur
            cuts[#cuts + 1] = t
            focus[#focus + 1] = v.focus
            names[#names + 1] = name
            prev = name
        end
    end
    return { name = 'afk_showroom', keys = keys, length = t, loop = true }, cuts, focus, names
end

--- Another player close by to give a shot to, or nil: the one kept from before while still in reach, else the
--- nearest within GUEST_M. Not anyone in our own vehicle (they are in its shots already).
local function findGuest(center, keep)
    local me = PlayerPedId()
    local mine = GetVehiclePedIsIn(me, false)
    local function fits(ped, within)
        if not ped or ped == 0 or ped == me or not DoesEntityExist(ped) or not IsEntityVisible(ped) then return false end
        if mine ~= 0 and GetVehiclePedIsIn(ped, false) == mine then return false end
        return #(GetEntityCoords(ped) - center) <= within
    end
    if fits(keep, GUEST_KEEP_M) then return keep end
    local best, bestD = nil, GUEST_M
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if fits(ped, bestD) then best, bestD = ped, #(GetEntityCoords(ped) - center) end
    end
    return best
end

--- The sequence for this vehicle now.
---@return table|nil seq, integer[] cuts, table focus, string[] names, string kind
local function build(veh, guest)
    local kind, len = kindOf(veh)
    local set = SETS[kind] or SETS.car
    local list = set[isNight() and 'night' or 'day']
    local rain = GetRainLevel() > 0.2
    if rain and (kind == 'car' or kind == 'truck') then
        list = { list[1], 'puddle', table.unpack(list, 2) }
    end
    if sunHeading() and not rain then list = { 'golden', table.unpack(list) } end
    if guest then list = { 'guest', table.unpack(list) } end
    local seq, cuts, focus, names = assemble(list, {
        scale = math.max(0.6, math.min(3.0, len / CAR_LENGTH)), slow = rain and 0.8 or 1.0, stretch = rain and 1.15 or 1.0,
        subjects = { car = veh, guest = guest }, ents = { car = veh, player = PlayerPedId(), guest = guest }, ignore = veh,
    })
    return seq, cuts, focus, names, kind
end

-- ---- what the corner shows ----

--- The make's label and logo key (whip_core's html/img/manufacturers/; the page hides a logo that is not there), and
--- the model's name.
local function labels(veh)
    local model = GetEntityModel(veh)
    local name = GetLabelText(GetDisplayNameFromVehicleModel(model))
    if name == 'NULL' then name = GetDisplayNameFromVehicleModel(model) end
    local make, logo = nil, nil
    -- pcall'd: documented as crashing on game builds at or below 1868 (client/garage_spots.lua).
    local ok, raw = pcall(GetMakeNameFromVehicleModel, model)
    if ok and raw and raw ~= '' and raw ~= 'CARNOTFOUND' then
        local label = GetLabelText(raw)
        make = label ~= 'NULL' and label or raw
        local key = raw:lower()
        logo = LOGO_SPELLING[key] or key
    end
    local plate = GetVehicleNumberPlateText(veh)
    plate = plate and plate:match('^%s*(.-)%s*$') or ''
    return make, logo, name, plate
end

--- The vehicle's numbers against the best of its class (GTA's figures, as the game's own stats screen draws
--- them): shares 0 to 1, the top speed in the player's unit (the dial's), and the class's name. Boats and aircraft
--- get speed and acceleration only. nil when the game will not say.
local function performance(veh, kind)
    local ok, out = pcall(function()
        local class = GetVehicleClass(veh)
        local function share(v, best) return (best and best > 0) and math.max(0.0, math.min(1.0, v / best)) or 0.0 end
        local top = GetVehicleEstimatedMaxSpeed(veh)
        local kmh = exports.whip_core:GetPlayerSetting('dial.speedUnit') == 'kmh'
        local rows = {
            { label = 'Top speed', share = share(top, GetVehicleClassEstimatedMaxSpeed(class)),
              text = ('%d %s'):format(math.floor(top * (kmh and 3.6 or 2.23694) + 0.5), kmh and 'km/h' or 'mph') },
            { label = 'Acceleration', share = share(GetVehicleAcceleration(veh), GetVehicleClassMaxAcceleration(class)) },
        }
        if kind ~= 'boat' and kind ~= 'air' then
            rows[#rows + 1] = { label = 'Braking', share = share(GetVehicleMaxBraking(veh), GetVehicleClassMaxBraking(class)) }
            rows[#rows + 1] = { label = 'Traction', share = share(GetVehicleMaxTraction(veh), GetVehicleClassMaxTraction(class)) }
        end
        local name = GetLabelText(('VEH_CLASS_%d'):format(class))
        return { class = name ~= 'NULL' and name or nil, rows = rows }
    end)
    return ok and out or nil
end

--- The portrait's sequence round the player on foot now.
local function buildFoot(guest)
    local ped = PlayerPedId()
    local list = SETS.foot[isNight() and 'night' or 'day']
    if sunHeading() and GetRainLevel() <= 0.2 then list = { 'fgolden', table.unpack(list) } end
    if guest then list = { 'guest', table.unpack(list) } end
    return assemble(list, { scale = 1.0, slow = 1.0, stretch = 1.0, subjects = { guest = guest },
                            ents = { player = ped, guest = guest }, ignore = ped })
end

--- On foot: where they are, as the map names it (the street, and the area).
local function placeLabel(ped)
    local p = GetEntityCoords(ped)
    local hash = GetStreetNameAtCoord(p.x, p.y, p.z)
    local street = hash and hash ~= 0 and GetStreetNameFromHashKey(hash) or ''
    local area = GetLabelText(GetNameOfZone(p.x, p.y, p.z))
    if area == 'NULL' then area = '' end
    if street ~= '' and area ~= '' then return street .. ' · ' .. area end
    return street ~= '' and street or area
end

-- The game's makes whose logo file is spelt otherwise.
LOGO_SPELLING = { emperor = 'emporer' }

-- ---- running ----

---@type table|nil
local run = nil   -- { veh (what it shows: the vehicle, or the player), gen, length, cuts, focus, names, guest, rebuild,
                  --   loopStart, nextCut, dofOn, lights, photoTried }
local photo = nil -- the last showroom's picture (a data URL), until client/main.lua takes it

--- Put the sequence up and the page over it. `watch`: the entity it is about (gone: it ends). `rebuild(guest)`
--- answers the sequence again with another guest (or none): seq, cuts, focus, names, subjects.
local function play(seq, cuts, focus, names, subjects, watch, card, guest, rebuild)
    local ok = exports.whip_core:PlayCameraSequence(seq, {
        subjects = subjects, transitionIn = IN_MS, transitionOut = OUT_MS, async = true,
    })
    if not ok then return false end
    photo = nil
    run = { veh = watch, cam = GetRenderingCam(), length = seq.length, cuts = cuts, loopStart = GetGameTimer(),
            startedAt = GetGameTimer(), nextCut = 1, focus = focus, names = names, dofOn = false, night = isNight(),
            guest = guest, rebuild = rebuild, frames = 0 }
    exports.whip_core:HoldCleanScreen(CLEAN)
    card.action, card.on = 'afk', true
    SendNUIMessage(card)
    return true
end

--- Start it round `veh`. `idleMs`: how long they have been away already (the corner's clock starts there).
---@return boolean started
function Showroom.start(veh, idleMs)
    if run or not DoesEntityExist(veh) then return false end
    local guest = findGuest(GetEntityCoords(veh))
    local seq, cuts, focus, names, kind = build(veh, guest)
    if not seq then return false end
    local make, logo, name, plate = labels(veh)
    local function rebuild(g)
        local s2, c2, f2, n2 = build(veh, g)
        return s2, c2, f2, n2, { car = veh, guest = g }
    end
    if not play(seq, cuts, focus, names, { car = veh, guest = guest }, veh, {
        kind = kind, make = make, logo = logo, model = name, plate = plate, stats = performance(veh, kind),
        idleMs = math.floor(idleMs or 0) }, guest, rebuild) then
        return false
    end
    -- The lights: only the game that drives it may, and only the driver's own, given back as GTA's normal.
    if GetPedInVehicleSeat(veh, -1) == PlayerPedId() and NetworkHasControlOfEntity(veh) then
        SetVehicleLights(veh, 2)
        run.lights = true
    end
    return true
end

--- Start the portrait round the player on foot.
---@return boolean started
function Showroom.startOnFoot(idleMs)
    if run then return false end
    local ped = PlayerPedId()
    local guest = findGuest(GetEntityCoords(ped))
    local seq, cuts, focus, names = buildFoot(guest)
    if not seq then return false end
    local function rebuild(g)
        local s2, c2, f2, n2 = buildFoot(g)
        return s2, c2, f2, n2, { guest = g }
    end
    local name = exports.whip_core:GetPlayerFullName(GetPlayerServerId(PlayerId())) or GetPlayerName(PlayerId())
    return play(seq, cuts, focus, names, { guest = guest }, ped, { kind = 'foot', make = placeLabel(ped), model = name,
                                             idleMs = math.floor(idleMs or 0) }, guest, rebuild)
end

--- Stop it and hand back to the game's camera (a soft blend). Fine when it is not up.
function Showroom.stop()
    local r = run
    if not r then return end
    run = nil
    SendNUIMessage({ action = 'afk', on = false })
    exports.whip_core:ReleaseCleanScreen(CLEAN)
    if r.lights and DoesEntityExist(r.veh) and NetworkHasControlOfEntity(r.veh) then
        SetVehicleLights(r.veh, 0)
        if r.beam then SetVehicleFullbeam(r.veh, false) end
        if r.cabin then SetVehicleInteriorlight(r.veh, false) end
    end
    -- Only our own camera: StopCamera leaves one another resource put up.
    exports.whip_core:StopCamera()
end

---@return boolean
function Showroom.active() return run ~= nil end

--- The last showroom's photo (a data URL), once: taken by the "welcome back" card. nil when none was taken.
---@return string|nil
function Showroom.takePhoto()
    local p = photo
    photo = nil
    return p
end

--- A guest came or went: the sequence built again with them in (or out) and put up in the black of a fade, from its
--- first shot, no blend (the picture is black). The page and the clean screen stay as they are.
local function restart(r, guest)
    if run ~= r or not r.rebuild then return end
    local seq, cuts, focus, names, subjects = r.rebuild(guest)
    if not seq then return end
    if not exports.whip_core:PlayCameraSequence(seq, { subjects = subjects, transitionIn = 0, transitionOut = OUT_MS, async = true }) then return end
    r.cam, r.length, r.cuts, r.focus, r.names, r.guest = GetRenderingCam(), seq.length, cuts, focus, names, guest
    r.loopStart, r.nextCut, r.dofOn = GetGameTimer(), 1, false
end

--- Set by client/idle.lua: called as each fade through black starts (a standing pose changes in the black).
---@type function|nil
Showroom.onDip = nil

--- The shot's focus point in the world: its aim on its subject (the vehicle, the player, or the guest). nil when
--- that is gone.
local function focusPoint(r, f)
    local ent = (f.subject == 'player' and PlayerPedId()) or (f.subject == 'guest' and r.guest) or r.veh
    if not ent or not DoesEntityExist(ent) then return nil end
    return aimPoint(ent, f.aim)
end

--- This frame's depth of field for shot `i`: the focus point sharp, the rest soft. GTA
--- keeps its shallow mode only while it is asked for every frame (SetUseHiDof).
local function focusFrame(r, i)
    local cam = r.cam
    if not cam or cam == -1 then return end
    local f = r.focus[i]
    if not f then
        if r.dofOn then SetCamUseShallowDofMode(cam, false); r.dofOn = false end
        return
    end
    local at = focusPoint(r, f)
    if not at then return end
    local d = #(GetCamCoord(cam) - at)
    if not r.dofOn then SetCamUseShallowDofMode(cam, true); r.dofOn = true end
    SetCamNearDof(cam, math.max(0.1, d * (DOF_NEAR + DOF_NEAR_K * f.dof)))
    SetCamFarDof(cam, d * (DOF_FAR - DOF_FAR_K * f.dof))
    SetCamDofStrength(cam, 0.5 + 0.5 * f.dof)
    SetUseHiDof()
end

--- This frame's lights for shot `i`, `ts` ms into it (LIGHT_FX). Natives only on a change, but the brake lights,
--- which GTA holds only for the frame they are asked in.
local function lightsFrame(r, i, ts)
    if not r.lights then return end
    local fx = LIGHT_FX[r.names[i]]
    local beam = false
    if fx and fx.flash then
        for _, step in ipairs(FLASH) do
            if ts >= step[1] then beam = step[2] end
        end
    end
    if beam ~= (r.beam or false) then SetVehicleFullbeam(r.veh, beam); r.beam = beam end
    local cabin = (fx and fx.cabin and r.night) or false
    if cabin ~= (r.cabin or false) then SetVehicleInteriorlight(r.veh, cabin); r.cabin = cabin end
    if fx and fx.brake then SetVehicleBrakeLights(r.veh, true) end
end

--- Is our camera still the one up? GTA's rendering camera is ours (learnt once the blend in has settled); whip_core's
--- own word is asked every half second or so (an export, not every frame).
local function stillOurs(r)
    r.frames = r.frames + 1
    local now = GetGameTimer()
    if now - r.startedAt < IN_MS + 500 then return true end
    local rendering = GetRenderingCam()
    if not r.settled then
        r.settled, r.cam = true, rendering
    elseif rendering ~= r.cam then
        return false
    end
    if r.frames % 30 == 0 and not exports.whip_core:IsCameraActive() then return false end
    return true
end

--- Each frame while it plays (from the AFK frame loop): the fade before each cut and the focus. Answers false when the showroom
--- has gone from under it: another camera replaced it, or what it shows is gone.
---@param now integer GetGameTimer()
---@return boolean
function Showroom.frame(now)
    local r = run
    if not r then return true end
    if not DoesEntityExist(r.veh) or not stillOurs(r) then return false end
    -- As the camera's loop counts: past the end it starts again from this frame.
    local t = now - r.loopStart
    if t > r.length then
        r.loopStart, t, r.nextCut = now, 0, 1
    end
    local cut = r.cuts[r.nextCut]
    if cut and t >= cut - DIP_LEAD_MS then
        r.nextCut = r.nextCut + 1
        SendNUIMessage({ action = 'afkDip' })
        if Showroom.onDip then Showroom.onDip() end
        -- A guest who came or went: taken in or out in the black.
        local guest = findGuest(GetEntityCoords(r.veh), r.guest)
        if guest ~= r.guest then SetTimeout(DIP_BLACK_MS, function() restart(r, guest) end) end
    end
    -- The photo, once, in the middle of the second shot.
    if not r.photoTried and r.cuts[2] and t >= r.cuts[1] + PHOTO_AT and t < r.cuts[2] - DIP_LEAD_MS - 300 then
        r.photoTried = true
        CreateThread(function()
            local data = exports.whip_core:TakeScreenshot({ format = 'jpg', quality = 0.85, width = 480 })
            if type(data) == 'string' then photo = data end
        end)
    end
    local i = 1
    while r.cuts[i] and t >= r.cuts[i] do i = i + 1 end
    focusFrame(r, i)
    lightsFrame(r, i, t - (r.cuts[i - 1] or 0))
    return true
end

-- This resource stopping: the camera and the clean screen are let go by whip_core (it sweeps a stopped resource's);
-- the lights are the car's, given back here.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not run then return end
    if run.lights and DoesEntityExist(run.veh) then
        SetVehicleLights(run.veh, 0)
        SetVehicleFullbeam(run.veh, false)
        if run.cabin then SetVehicleInteriorlight(run.veh, false) end
    end
end)
