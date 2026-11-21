#!/usr/bin/env python3
"""Takes WSGForever's README and CurseForge screenshots from the running game.

Captions are real game tooltips drawn by the WSGForeverShots helper addon,
anchored to the addon's own frames, so nothing is lettered afterwards and the
shots follow wherever you have moved the frames.

Needs: the game running and in the world (any character, ideally in a city),
and the helper installed, which needs a game restart the first time:
  shoot.py install      copy the helper addon into the AddOns folder
  shoot.py dump         record where the frames are (reloads the UI once)
  shoot.py shots [name] take every shot, or the named ones, into media/
  shoot.py uninstall    remove the helper addon again

It types into the game's chat with a "/p " prefix, so nothing ever goes out
as a whisper, and it reloads the UI, so don't run it mid-match.

Machine-specific settings come from the environment (see README.md):
  WSGF_HELPERS     folder with bot.py (WINE, WINPY: Wine binary and a Windows
                   Python folder with postkey.py) and vis.py (window_id())
  WSGF_WINEPREFIX  the game's Wine prefix
"""
import json, os, re, shutil, subprocess, sys, time

for var in ("WSGF_HELPERS", "WSGF_WINEPREFIX"):
    if not os.environ.get(var):
        sys.exit(f"set {var} first (see tools/screenshots/README.md)")
sys.path.insert(0, os.environ["WSGF_HELPERS"])
import bot, vis  # noqa: E402
from PIL import Image  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ADDONS = os.path.dirname(REPO)
HELPER = os.path.join(HERE, "WSGForeverShots")
INSTALLED = os.path.join(ADDONS, "WSGForeverShots")
SAVED = os.path.join(ADDONS, "..", "..", "WTF", "Account")
OUT = os.path.join(REPO, "media", "gallery")
ENV = dict(os.environ, WINEPREFIX=os.environ["WSGF_WINEPREFIX"], WINEDEBUG="-all")
WINPY_WIN = "Z:" + bot.WINPY.replace("/", "\\")  # the same folder as Windows sees it

# Each shot: lines to run first, the frames to crop around, and extra room on
# each side (left, top, right, bottom). Captions are in the helper addon.
SHOTS = {
    "enemy-frames": dict(run=["/run WSGForever.SetEnemyStyle('flat')"], crop=["WSGForeverEnemies"], pad=(420, 40, 40, 40)),
    "timers": dict(run=[], crop=["WSGForeverFlagSpawn", "WSGForeverEFCLow", "WSGForeverMatchTimer", "WSGForeverRezTimer"],
                   pad=(440, 60, 80, 40)),
    "callout-bar": dict(run=["/run WSGForever.modules.Callouts.abFrame:Hide()"], crop=["WSGForeverCallouts"], pad=(40, 110, 40, 30)),
    "ab-callouts": dict(run=["/run local c=WSGForever.modules.Callouts c.frame:Hide() c.abFrame:Show()"],
                        crop=["WSGForeverABCallouts"], pad=(60, 110, 60, 30)),
    "queue-timers": dict(run=[], crop=["WSGForeverQueue"], pad=(380, 50, 50, 40)),
    "settings": dict(run=["/fc"], crop=["WSGForeverOptions"], pad=(30, 30, 30, 30)),
    "match-history": dict(
        run=["/fc history",
             "/run local h=WSGForever.modules.History local v=h.views[#h.views].hovers[1] v:GetScript('OnEnter')(v)"],
        crop=["WSGForeverOptions"], pad=(30, 30, 520, 30)),
}
STYLES = ["flat", "classic", "raid", "dark", "darkcompact", "large"]


def say(text):
    """Type one line into the game's chat (party prefix: never a whisper)."""
    helper = os.path.join(HERE, "_type.py")
    with open(helper, "w") as f:
        f.write("import sys, time\nsys.path.insert(0, r'" + WINPY_WIN + "')\n"
                "import postkey\npostkey.press('enter')\ntime.sleep(0.25)\n"
                "for c in sys.argv[1]:\n    postkey.u.PostMessageW(postkey.h, 0x102, ord(c), 1)\n    time.sleep(0.02)\n")
    run = lambda *a: subprocess.run([bot.WINE, bot.WINPY + "/python.exe", *a], env=ENV,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not text.startswith("/p "):
        text = "/p " + text
    run("Z:" + helper.replace("/", "\\"), text)
    time.sleep(0.3)
    run(bot.WINPY + "/postkey.py", "enter")
    os.unlink(helper)


def capture(path):
    wid = vis.window_id()
    if not wid:
        sys.exit("the game isn't running")
    subprocess.run(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "enable" })'], capture_output=True)
    time.sleep(0.5)
    subprocess.run(["grim", "-T", wid, path], timeout=10, check=True)


def reload():
    say("/reload")
    time.sleep(28)


def rects():
    import glob
    path = max(glob.glob(os.path.join(SAVED, "*", "SavedVariables", "WSGForeverShots.lua")), key=os.path.getmtime)
    lua = open(path).read()
    out = {}
    for name, nums in re.findall(r'\["(\w+)"\] = \{\s*([-\d,\s]+?)\s*\}', lua):
        out[name] = [int(n) for n in re.findall(r"-?\d+", nums)]
    return out


def crop(img, boxes, pad, size=(1280, 720)):
    l = min(b[0] for b in boxes) - pad[0]
    t = min(b[1] for b in boxes) - pad[1]
    r = max(b[2] for b in boxes) + pad[2]
    b = max(b[3] for b in boxes) + pad[3]
    # Widen the box to the output's shape before scaling, so nothing is stretched.
    w, h = r - l, b - t
    want = size[0] / size[1]
    if w / h < want:
        grow = int(h * want) - w
        l, r = l - grow // 2, r + grow - grow // 2
    else:
        grow = int(w / want) - h
        t, b = t - grow // 2, b + grow - grow // 2
    W, H = img.size
    l, t = max(0, l), max(0, t)
    r, b = min(W, r), min(H, b)
    return img.crop((l, t, r, b)).resize(size, Image.LANCZOS)


def shoot(names):
    boxes = rects()
    os.makedirs(OUT, exist_ok=True)
    say("/run WSGForever.SetTestMode(true)")
    time.sleep(1.5)
    for name in names:
        spec = SHOTS[name]
        for line in spec["run"]:
            say(line)
            time.sleep(0.8)
        say(f"/run WSGFShot.Stage('{name}')")
        time.sleep(0.5)
        say("/run GameTooltip:Hide()") if not name == "match-history" else None
        time.sleep(1.2)
        raw = os.path.join(HERE, "_raw.png")
        capture(raw)
        have = [boxes[f] for f in spec["crop"] if f in boxes]
        if not have:
            print(f"{name}: none of {spec['crop']} were on screen when the frames were recorded; skipped")
            continue
        crop(Image.open(raw).convert("RGB"), have, spec["pad"]).save(os.path.join(OUT, name + ".jpg"), quality=88)
        print("saved", name)
        say("/run WSGFShot.Clear()")
        if name in ("settings", "match-history"):
            say("/fc options")
        say("/run local c=WSGForever.modules.Callouts c:Refresh()")
        time.sleep(0.5)
    say("/run WSGForever.SetTestMode(false)")
    os.unlink(os.path.join(HERE, "_raw.png"))


def shoot_styles():
    """One image with the enemy frames in several styles side by side."""
    boxes = rects()
    say("/run WSGForever.SetTestMode(true)")
    time.sleep(1.5)
    tiles = []
    raw = os.path.join(HERE, "_raw.png")
    for style in STYLES:
        say(f"/run WSGForever.SetEnemyStyle('{style}')")
        time.sleep(2.5)
        capture(raw)
        e = boxes["WSGForeverEnemies"]
        tiles.append(Image.open(raw).convert("RGB").crop((e[0] - 20, e[1] - 30, e[0] + 300, e[1] + 470)))
    say("/run WSGForever.SetEnemyStyle('flat')")
    say("/run WSGForever.SetTestMode(false)")
    sheet = Image.new("RGB", (len(tiles) * 320, 500))
    for i, t in enumerate(tiles):
        sheet.paste(t, (i * 320, 0))
    k = 1280 / sheet.width
    sheet.resize((1280, int(500 * k)), Image.LANCZOS).save(os.path.join(OUT, "enemy-styles.jpg"), quality=88)
    os.unlink(raw)
    print("saved enemy-styles")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "install":
        shutil.rmtree(INSTALLED, ignore_errors=True)
        shutil.copytree(HELPER, INSTALLED)
        print("installed; restart the game (not just /reload) the first time so it loads")
    elif cmd == "uninstall":
        shutil.rmtree(INSTALLED, ignore_errors=True)
        print("removed")
    elif cmd == "dump":
        say("/run WSGForever.SetTestMode(true)")
        time.sleep(1.5)
        say("/run WSGForever.modules.Callouts.abFrame:Show() WSGForever.modules.Options:Open('settings')")
        time.sleep(1)
        say("/run WSGFShot.Dump()")
        time.sleep(0.5)
        say("/run WSGForever.SetTestMode(false)")
        reload()
        print(json.dumps(rects(), indent=1))
    elif cmd == "shots":
        names = sys.argv[2:] or list(SHOTS)
        shoot([n for n in names if n != "enemy-styles"])
        if not sys.argv[2:] or "enemy-styles" in names:
            shoot_styles()
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
