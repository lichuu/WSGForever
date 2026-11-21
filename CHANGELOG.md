# WSGForever

## Unreleased
- The match timer now starts when the gates open, not when the battleground is created. It keeps its time through a reload, and works out the start when you join a match already under way.

## 0.8.0
- Match timer: a small clock beside the score showing how long the battleground has been running, in every battleground. Drag it anywhere with `/fc unlock`.
- Fixed the enemy frames emptying after you clicked the Alliance or Horde tab on the game's scoreboard. That tab also limits what addons can see; the addon now waits for the scoreboard to close and switches it back to All.
- Arathi Basin callouts: a second callout bar appears in Arathi Basin with Incoming, Big incoming, Safe and Help for each of the five nodes, each with its own icon. Each can be bound to a key, and the bar moves and resizes separately (`/fc scale abcallouts`).
- Match history: hover a match to see its final scoreboard: both teams in class colours with each player's kills, deaths, honorable kills and honor. Matches imported from Nova Instance Tracker show your own team's names only; click the import button again to add them to matches you already imported.

## 0.7.0
- Enemy frame styles: eleven looks to choose from in a dropdown on the settings tab (Flat, Classic, Raid frames, Dark, Compact, Dark compact, Slim, Large, Minimal with no class icons, ElvUI and EllesmereUI), or with `/fc style <name>`.
- Bar texture and font: two more dropdowns pick these separately, including any that your other addons share. The font also applies to the team name and count above the list.
- Enemy names can be turned off on the settings tab, for bars and class icons only.
- ElvUI and EllesmereUI styles. When that UI is running, the enemy frames follow its settings: ElvUI's unit frame bar texture, font, size, outline and health colour; EllesmereUI's font, outline and class colours. Without it, they use a look in its manner.

## 0.6.1
- Fixed pinging or focusing an enemy who is too far away to target: it used to ping or focus whoever you already had targeted. Now it does nothing.

## 0.6.0
- Match history: every battleground you finish is recorded with the result, flag score, length and your scoreboard line (kills, deaths, honor, captures, returns). It is on the new Match history tab of the settings window, or `/fc history`. `/fc record` turns recording off.
- If you use Nova Instance Tracker, the history tab can import the battlegrounds it already recorded.
- Key bindings: every callout, plus "target enemy flag carrier", "ping enemy flag carrier", "ping our flag carrier", "open settings" and "open match history", can be bound in the game's Key Bindings menu under WSGForever.
- `/fc who` lists who else in your group has WSGForever and their version, and you are told once when someone has a newer one.
- `/fc` now opens the settings window, and `/fc help` lists the chat commands. The per-feature commands such as `/fc enemies` still work but are no longer listed, since each is a checkbox.
- The settings window shows which version you have.
- A launcher for info bars and minimap-button collectors, when one is installed.

## 0.5.0
- Battlefield map: teammates show as larger dots in their class colours. `/fc scale map` and `/fc scale mapdots` change the map and dot sizes; `/fc bgmap` turns it off.
- Shorter descriptions on the settings page so none are cut off.

## 0.4.0
- Minimap button: left click opens settings, right click unlocks the frames for moving, drag to move the button.
- Settings page with every feature toggle and the layout tools. It is also listed under Options > AddOns. All `/fc` commands still work.
- Fixed "Dropped - returns in" showing while the flag was still being carried.
- The drop countdown no longer covers the flag icon or the carrier frames.
- The drop countdown now runs for 12 seconds.
- Removed the flag spawn time setting; it is always 12 seconds.

## 0.3.2
- Releases are now built and published automatically.
- The download now includes the MIT license.

## 0.3.1
- Callout bar labels are centred on their buttons.

## 0.3.0
- Middle click pings with the game's own ping system: Attack on an enemy row or the enemy flag carrier, Assist on your own carrier.
- The addon list icon is now the Warsong Gulch mark.

## 0.2.0
- FlagCarriers is now WSGForever.
- Flag spawn timer after a capture.
- `/fc scale` to size every element.
- The rez timer runs in every battleground.
- Fixed false "Dropped" countdowns, missed rez waves, and frames drawing over bags.
