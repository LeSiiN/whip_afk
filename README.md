# whip_afk

AFK for [whip](https://whipfx.net). A player with no input for a while is marked away:

- **Others** see an `AFK · 3 min` tag over their head, in the look of whip's /me bubbles.
- **Their own camera** shows off the car they sit in (it standing still) or makes a portrait of them on foot: slow
  shots in a shuffled order with depth of field and fades through black, thin cinema bars, the car's make, model,
  plate and numbers (or their name and where they are), a drone shot, a shot into the sun at sunrise and sunset, and a
  shot of whoever stands close by. Every shot is tried against the walls first, so a garage or a flat gets only the
  shots that fit.
- **Their character** does what fits where they are: sits on the couch at home or a bench close by, leans on a wall or
  a rail, sits in the sand or the grass, talks with another player who is away, checks their phone; in a car an arm on
  the window or nodding to the radio.
- **Any key** brings them back: the camera blends home, the pose ends properly (they stand up before they can walk
  off), and a card says welcome back, how long they were away, and shows a photo from the showroom.

Nothing runs every frame while nobody is away: the check for input is once a second (`/whipcost` lists it).

## Install

Put `whip_afk` in your resources and start it after whip_core:

```
ensure whip_core
ensure whip_afk
```

## Settings

- **Server:** `/whip` → Settings → AFK (config.lua holds the defaults): on/off, the delay, the camera, the idle
  animations, the tag and its range, see-through while away.
- **Each player:** the pause menu → Settings → Server → AFK: the camera, the idle animation, their own delay.

## For other resources

- The player's statebag `whip_afk`: `os.time()` at their last input while they are away, absent otherwise. Written by
  the server only (it is under whip's Sentinel).
- The local event `whip_afk:changed`: `{ source, afk }` on the server, `{ afk, showroom }` on the player's game.

## Licence

LGPL-3.0, as whip itself: see `COPYING` and `COPYING.LESSER`.
