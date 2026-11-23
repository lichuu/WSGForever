# Screenshots

`shoot.py` takes the addon's README and CurseForge images from the running game.
Captions are real game tooltips, drawn by the small `WSGForeverShots` helper addon and
anchored to WSGForever's own frames, so nothing is lettered in an image editor and the
shots follow your frame layout.

It needs two settings for your machine, as environment variables (nothing personal is kept in the repo):

- `WSGF_HELPERS`: a folder with `bot.py` (defining `WINE`, the Wine binary, and `WINPY`, a Windows Python folder containing a `postkey.py` that posts keys to the game window) and `vis.py` (defining `window_id()`, the game window's id for `grim -T`).
- `WSGF_WINEPREFIX`: the game's Wine prefix.

A local wrapper that sets them is the easiest way; keep it out of git.

1. `python3 tools/screenshots/shoot.py install`, then start the game (a restart is needed
   the first time so the helper loads). Stand somewhere with a nice background, out of combat.
2. `python3 tools/screenshots/shoot.py dump` records where the frames are (one UI reload).
3. `python3 tools/screenshots/shoot.py shots` writes every image to `media/gallery/`,
   or name some: `shots enemy-frames timers`.
4. `python3 tools/screenshots/shoot.py uninstall` when done.

It types into chat with a `/p ` prefix so nothing can go out as a whisper, and it
reloads the UI, so don't run it in a match. Shots and captions are listed in `SHOTS`.
The scoreboard's Time Elapsed tab is the exception: it needs players on the board, so
the helper takes that one by itself. With the helper installed, open the scoreboard in a
real battleground two minutes or more in; it captions the tab and has the game save its
own screenshot (in the game's `Screenshots` folder), up to four times. Crop the best one
into `media/gallery/scoreboard-time.jpg` by hand, then uninstall the helper.

The `tools` folder is left out of the addon download.
