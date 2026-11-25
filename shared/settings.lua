-- config.lua as a page in /whip → Settings → AFK. Each key is a path into Config; config.lua's value is the default.

local ON = { path = 'Enabled', equals = true }

Whip.configPage({
    label = 'AFK',
    settings = {
        { key = 'Enabled', type = 'bool', label = 'AFK',
          help = 'A player with no input for a while is marked away: others see an AFK tag over their head, and other resources can tell (the whip_afk statebag). Any key brings them back.' },
        { key = 'Delay', type = 'int', min = 15, max = 1800, step = 5, unit = 's', label = 'Away after', shownWhen = ON,
          help = 'Seconds with no input before a player is marked away. Each player may choose their own in the pause menu.' },
        { key = 'Showroom', type = 'bool', label = 'Cinematic camera', shownWhen = ON,
          help = 'While a player is away their camera shows them off: in a stopped vehicle slow shots round it, its lights on, its make, model, plate and numbers in a corner; on foot a portrait, with their name and where they are. Each player may turn it off for themselves.' },
        { key = 'IdleEmotes', type = 'bool', label = 'Idle animations', shownWhen = ON,
          help = 'A player who is away does what fits where they are, as others see it too: sits on the couch at home or a bench close by, leans on a wall or a rail, sits in the sand or the grass, talks with another player who is away, checks their phone; in a car an arm on the window or nodding to the radio. On their return the pose ends properly before they can move. Each player may turn it off for themselves.' },
        { key = 'Bubble', type = 'bool', label = 'AFK tag over the head', shownWhen = ON,
          help = 'Players nearby see "AFK · 3 min" over the head of a player who is away.' },
        { key = 'BubbleRange', type = 'number', min = 5, max = 100, step = 1, unit = 'm', label = 'AFK tag seen from',
          shownWhen = { path = 'Bubble', equals = true },
          help = 'Players further away do not see the tag.' },
        { key = 'Ghost', type = 'bool', label = 'See-through while away', shownWhen = ON,
          help = 'A player who is away is see-through to others and nothing bumps into them, nor into the car they drive.' },
    },
})
