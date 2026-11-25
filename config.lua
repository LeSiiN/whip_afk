-- Defaults. Admins change these in game (/whip → Settings → AFK); saved values win over this file and are written
-- into Config on both sides.
--
--   Enabled     false: nobody is ever marked away
--   Delay       seconds with no input before a player is away (each player may choose their own in the pause menu)
--   Showroom    the camera shows off the car they sit in (it standing still) or makes a portrait of them on foot;
--               each player may turn it off for themselves
--   IdleEmotes  their character does what fits where they are: the couch at home, a bench, a wall, the sand, a talk
--               with another player who is away, an arm on the car window (each player may turn it off)
--   Bubble      others see the AFK tag over the head; BubbleRange: from how far (metres)
--   Ghost       players who are away are see-through and nothing bumps into them (nor their car, if they drive it)
Config = {
    Enabled     = true,
    Delay       = 60,
    Showroom    = true,
    IdleEmotes  = true,
    Bubble      = true,
    BubbleRange = 20.0,
    Ghost       = false,
}
