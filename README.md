<p align="center"><img src="media/logo.svg" width="180" alt="WSGForever logo"></p>

<h1 align="center">WSGForever</h1>

A Warsong Gulch addon for **WoW Forever** (interface 16001).

## Features
- **Callout bar**: one-click location callouts to instance chat (FR, TUN, ROOF, RAMP, GY, MID and more), plus an "EFC LOW" button.
- **Carrier HP**: health shown next to Blizzard's flag carrier names, with drop/return timers.
- **Flag spawn timer**: countdown to the flags spawning again after a capture.
- **EFC LOW banner**: a local alert when the enemy flag carrier is under 50% HP.
- **Carrier frames**: moves Blizzard's carrier frames next to the flags.
- **Enemy frames**: battleground enemy list with HP, mana, dead/alive, range, targeted-by count and a carrier highlight. Left click a row to target, right click to focus, middle click to ping Attack.
- **Rez timer**: graveyard wave countdown in any battleground and how many enemies are waiting to rez.
- **FC icon**: flag icon on your team's carrier in the raid frames.
- **Auto assist**: gives everyone assist when you lead a battleground raid.
- **Settings**: a minimap button and a settings page (also under Options > AddOns) for every toggle, alongside the `/fc` commands.

## Install
Copy the `WSGForever` folder into `World of Warcraft/_forever_/Interface/AddOns/`.

## Commands
- `/fc unlock` / `/fc lock`: move frames by dragging; scroll over a frame to resize it.
- `/fc test`: preview everything outside a battleground.
- `/fc reset`: reset positions and sizes.
- `/fc scale`: list sizes; `/fc scale <name> <percent>` sets one (also covers the carrier text and raid flag icon, which can't be scrolled on).
- `/fc options`: open the settings window (also on the minimap button and under Options > AddOns).
- `/fc minimap`: show or hide the minimap button.
- `/fc <toggle>`: turn features on or off (`callouts`, `carriers`, `fcnames`, `blizzfc`, `lowalert`, `fcicon`, `rez`, `enemies`, `assist`).
- `/fc`: shows help and the current on/off state of every toggle.

## Tests
`lua5.1 tests/run.lua .` loads the addon into a small stand-in for the game and replays flag scenarios (drops, hand-offs, captures, returns) plus every command. It checks what the addon decides to show, not how it looks.

## Releasing
Work happens on a branch. Pushing it runs the tests; `main` only accepts commits the tests have passed on, so it is always releasable. A release is an annotated tag on `main`:

1. Merge the branch into `main` (fast-forward) and push.
2. Move the notes under "Unreleased" in `CHANGELOG.md` to a new version heading and push that to `main` the same way.
3. `git tag -a v1.2.3 -m v1.2.3 && git push origin v1.2.3`

The tag builds the zip, creates the GitHub release and triggers the CurseForge package. A tag that is not on `main` is refused.

## Credits
WSGForever stands on the shoulders of these, thank you:
- **vrjones1**: the [wsg rez timer and fc/efc hp](https://wago.io/cNXgQKDMd) WeakAura, which the rez timer and carrier HP are based on.
- **Bullsei**: [BattleGroundEnemies](https://github.com/BullseiWoWAddons/BattleGroundEnemies), the original enemy frames that inspired ours.
- **RBGDEV**: [BattleGroundEnemiesFixed](https://www.curseforge.com/projects/1444858), whose approach to targeting carriers and range checks on the modern client showed us the way.
- The **WeakAuras** team, for the addon the original auras were built in.

## License
[MIT](LICENSE)
