# Making mods for Bot Party

A mod can:

- **add party items**: new scenes and scripts, or the game's item scenes with new settings;
- **add maps** for party mode, made in the game's map editor or as Godot scenes;
- **add game modes**;
- **add looks**: hats, glasses and other things players wear;
- **replace textures** (any sprite in the game).

Mods are switched on and off in **Mods** (main menu). **Mods > Explore** finds
mods shared on GitHub (searchable, sorted by stars, date, name or downloads) and
installs them; **Browse...** installs a `.pck` from anywhere on your computer.
There are two kinds:

- **Mod packs** (`.pck` files), made in Godot. Everything in them works like the
  game's own files: scenes, scripts, pictures, sounds, map scenes with any nodes
  you like. This is the way to go.
- **Mod folders**: a folder with a `mod.json` and plain files (png pictures,
  `.gd` scripts, map files). No Godot needed, but pictures have to be loaded from
  scripts, and map scenes can't have nodes of their own.

Both use the same `mod.json`. A complete example is in
[`mods/example/`](mods/example): a pinball bumper, a long plank, a mint coin, a
game mode, a map file and a map scene with a windmill. Its pack, `example.pck`,
is on the [Releases page](https://github.com/AnCarsenat/bot-party/releases), with
two more mods have repositories of their own (and show up in **Mods > Explore**):
[Hats](https://github.com/AnCarsenat/bot-party-hats) (six looks) and
[Auction](https://github.com/AnCarsenat/bot-party-auction) (a game mode where
players bid for the cards). They're good starting points for a mod of your own,
release workflow included.

## Where mods go

**Mods > Open mods folder** opens the folder. Depending on your system,
it's here:

| System  | Folder |
|---------|--------|
| Linux   | `~/.local/share/godot/app_userdata/Bot Party/mods/` |
| Windows | `%APPDATA%\Godot\app_userdata\Bot Party\mods\` |
| macOS   | `~/Library/Application Support/Godot/app_userdata/Bot Party/mods/` |

```
mods/
  rockets.pck          a mod pack
  my-mod/              a mod folder
    mod.json
    rocket.png
    rocket.gd
    maps/
      long-jump.json
```

The pack's or folder's name is the mod's id (lower case). Item ids get it as a
prefix: item `rocket` in mod `rockets` is `rockets.rocket` (that's the name to
use with the console: `give rockets.rocket 1`). Keep a pack's file name when you
share it.

## Making a mod pack in Godot

You need the game's source (`git clone https://github.com/AnCarsenat/bot-party`)
and [Godot 4.7](https://godotengine.org/download). Open `project.godot`, then:

1. **Open `editor/mod_kit.tscn`** and select the **ModKit** node. Its buttons
   are in the inspector.
2. Type a name in **New mod** (lower case, like `rockets`) and press **Create the
   mod**. This makes `res://mods/rockets/` with a `mod.json` and a first map
   scene in `maps/`, and switches the mod on.
3. **Make your things in that folder**: scenes, scripts, pictures, sounds. Use
   the game's scenes and scripts as you like (`res://party/items/...`). List
   the items, modes and textures in `mod.json` (below). Paths in `mod.json` are
   relative to the mod folder, or full `res://` paths.
4. **Press F5** to try it. When the game runs from Godot, it uses your folder
   directly, so changes show up the next time you run it. (Mods in the project
   are off until you switch them on, in **Mods** or with **Switch it on
   in the game**.)
5. **Press Export the mod pack.** It writes `rockets.pck` into the game's mods
   folder, where the installed game finds it. Set **Copy to** to also put it
   somewhere to share. Give that file to other players.

Everything a mod pack needs must be inside its folder (or be part of the game).
Don't use `class_name` in mod scripts: refer to your scripts with `preload()`.
Mods in `res://mods/` are never part of the game's own builds.

From a terminal (for your own builds), after `godot --headless --import`:

```sh
godot --headless --path . --script res://editor/pack_mod.gd -- res://mods/rockets rockets.pck
```

When the game finds a pack and your project also has its folder (you're making
that mod), the folder wins: the pack would hide your latest changes.

## mod.json

```json
{
  "name": "My mod",
  "author": "You",
  "version": "1.0",
  "description": "One line shown in the Mods screen.",
  "icon": "icon.png",

  "items": {
    "rocket": {
      "name": "Rocket",
      "scene": "res://party/items/block.tscn",
      "script": "rocket.gd",
      "icon": "rocket.png",
      "size": [64, 64],
      "offset": [0, 0],
      "weight": 8,
      "props": { "modulate": "#ffb3c7" }
    }
  },

  "textures": {
    "party/art/coin.webp": "my_coin.png"
  },

  "maps": "maps"
}
```

Every key is optional except `name`.

`icon` is a picture shown in **Mods** and **Mods > Explore** when your mod is
selected: square, pixel art looks best (32x32 or 64x64, drawn big without
smoothing). Without the key, a file called `icon.png` is used if there's one.
Explore reads it from your repository (`mod.json`'s `icon`, or `icon.png`).

### Items

| Key | What it does |
|-----|--------------|
| `name` | Name on the pick card and in Party > Items. |
| `scene` | The item's scene: one of yours, or a game scene (`res://...`, list below). |
| `script` | A `.gd` file, added to the item (see below). Optional: your scene can have its own scripts. |
| `icon` | Picture on the pick card: one of yours, or a game texture (`res://...`). |
| `size` | `[width, height]` of the item in pixels. Used to stop building in the start and flag areas. |
| `offset` | Where that box sits from the item's centre, `[x, y]`. |
| `weight` | How often it shows up, 0 to 20. Built-in items use 5 to 10. Players can change it in Party > Items. |
| `props` | Properties set on the scene's root node, for example `"modulate": "#ff8080"` or `"one_way": true`. `[x, y]` becomes a Vector2 and `"#rrggbb"` a Color. |
| `host` | `true` if other items can hang from it (it needs a `mounts()` method, like the ferris wheel). |
| `bomb` | `true` for a bomb: it has no scene and destroys items within `radius` pixels. |
| `special` | `true` for a special item: it never shows up in the box itself, only out of Special crates. |
| `kind` | `"help"`, `"trap"` or `"bomb"`. Every box has at least one helpful item and one trap; items without a kind don't count for that. |

The game's item scenes you can start from:

```
res://party/items/block.tscn          res://party/items/spikes.tscn
res://party/items/saw.tscn            res://party/items/crossbow.tscn
res://party/items/plane_launcher.tscn res://party/items/crumble.tscn
res://party/items/conveyor.tscn       res://party/items/mine.tscn
res://party/items/fan.tscn            res://party/items/ferris.tscn
res://party/items/slider.tscn         res://party/items/pendulum.tscn
res://party/items/flamer.tscn         res://objects/platform.tscn
res://objects/trampoline.tscn
```

Some useful `props`:

- `res://objects/platform.tscn`: `size`, `one_way`, `move_offset`, `move_time`, `pause_time`;
- `res://objects/trampoline.tscn`: `bounce_speed`;
- `res://party/items/flamer.tscn`: `on_time`, `off_time`.

### Item scripts

The script is added as a child node of the item when it's placed, so
`get_parent()` is the item. It runs on every computer in an online game. Here's
the bumper from the example:

```gdscript
extends Node

var item: Node2D

func _ready() -> void:
	item = get_parent()
	# Your own picture: files sit next to the script.
	var folder := get_script().resource_path.get_base_dir()
	item.get_node("Sprite2D").texture = Mods.texture(folder.path_join("bumper.png"))
	...
```

Things you can use:

- `Mods.texture(path)`: loads a picture from your mod (works in packs and folders).
- Players are `CharacterBody2D` on physics layer 2 (mask `2` to detect them).
  - `player.bounce(speed, 1.0, direction)` launches a player, like a trampoline.
  - `player.velocity` is the player's velocity.
- To hurt players, add a `Hazard` (`res://party/hazard.gd`, an Area2D):
  touching it takes the player out, and the item's owner gets the trap points.
- To slow them down instead, add a `StatusArea` (`res://party/status_area.gd`)
  with `status` set to `stuck`, `slippery`, `slowed` or `floating`, and
  `seconds`. Or call `player.add_status("slippery", 2.0)` yourself.
  `player.pull(Vector2)` pulls a player for one frame (like the magnet).
- Online, each computer moves its own players' robots (the host follows them),
  so push, pull, bounce and give statuses only where `NetCheck.moves(player)` is
  true: on the computer that moves that robot. `Hazard` and `StatusArea` do it
  for you. Taking players out stays the host's job.
- `Party.session` holds the round, scores and placed items.

In a mod pack, your scenes can use your pictures like any Godot scene. In a mod
folder they can't (Godot only imports files that are part of a project): load
pictures with `Mods.texture()` from a script instead, like the bumper does.

### Maps

There are two ways to make maps:

- **In the game**: Party > Map editor. Ground is made of polygons of any
  shape. You can drag points, handles and shapes from the palette, and the
  editor snaps to the grid and to other objects.
- **In Godot**: open `editor/arena_template.tscn`, save it under a new name, and
  edit it with Godot's own tools:
  - `Ground/` holds Polygon2D nodes for the solid ground;
  - `Planks/` holds Polygon2D rectangles for one-way planks;
  - `Start` is a Polygon2D rectangle for the start area;
  - `Flag` is a Marker2D.

  Set the name in the inspector and press **Save map**. Run the scene (F6) to
  play it straight away. **Load the map file** brings an existing map into the
  scene.

Saved maps go to `maps/` next to `mods/`. Copy the `.json` files into a mod's
`maps` folder to share them. Mod maps show up in **Party > Arena**, marked "(mod)".

A map file looks like this (format 2):

```json
{
  "format": 2, "name": "Bumper alley", "author": "You",
  "ground": [ [[-192, 576], [448, 576], [448, 672], [-192, 672]] ],
  "planks": [ [896, 416, 192] ],
  "start": [-160, 384, 416, 192],
  "goal": [2208, 384],
  "wind": false, "meteors": false
}
```

`ground` is a list of polygons, each a list of `[x, y]` points (no
self-crossing). `planks` are `[x, y, width]`, `start` is `[x, y, width,
height]` and `goal` is where the flag stands, on top of ground.

### Items in maps

Maps can come with party items already in place (they're there from the start
of every party on that map, and can be blown up like the others). In the map
editor, drag them from the **Items** tab; T turns them, M flips them. In a file:

```json
"items": [ {"id": "saw", "x": 900, "y": 300, "rot": 0, "mirror": false} ]
```

`rot` is in quarter turns (0 to 3). Items from mods use their full id
(`my-mod.rocket`).

### Maps as Godot scenes

A map can also be a `.tscn` made from `editor/arena_template.tscn` (the mod kit's
**New map scene in this mod** makes one): put it in a mod's `maps` folder and
it's listed like the `.json` ones. Party items go under its `Items` node as
instances of the item scenes.

**In a mod pack, a map scene can have nodes of its own.** Everything next to
`Ground`, `Planks`, `Start`, `Flag` and `Items` is added to the arena when the
map is played: decorations, pictures, particles, lights, animated things,
scripts. The example's `windmill_hill.tscn` has a windmill whose sails turn
(`windmill.gd`). Online, each computer runs its own copy of these nodes, so keep
them to looks, or to motion that only depends on time, for things players touch.

A mod pack can be just maps: a `maps` folder, with or without a `mod.json`.

### Game modes

A mod can add ways to play party mode (Party > Rules > Mode):

```json
"modes": {
  "sudden_death": {
    "name": "Sudden death",
    "description": "First to the flag takes 15 points and ends the round.",
    "script": "sudden_death.gd"
  }
}
```

The script extends `PartyMode` (`party/party_mode.gd`) and overrides the hooks it
needs: `setup`, `round_started`, `process`, `player_finished` and `score_round`
(which can change the points of the round). Through `ctl` it can read
`ctl.slots`, `ctl.players`, `ctl.finished` and `ctl.run_time`, and call
`ctl.end_round()`, `ctl.say(text)` and `ctl.note(text)`. The example mod's
`sudden_death.gd` is about ten lines long.

A mode can also hand out the cards itself instead of first come, first served:
set `custom_pick = true`, then `pick_started(ctl)` runs when the box is filled
and `process_pick(ctl, delta)` every frame of picking. It fills `ctl.picks`
(slot -> card index in `ctl.box`), can read `ctl.cursors` (the card each player
stands on) and `ctl.pressed(slot, "action_1")`, calls `ctl.update_box()` after
changes, and `ctl.start_place()` when done. Online, everyone needs a mod that
adds modes, like mods that add items.

**Rules.** Each mode has its own rules in **Party > Rules** (changing the mode
brings out its rules, and keeps the other mode's for later). A mode can hide
standard rules it doesn't use (`hidden_rules = ["target", "coins"]`), give them
other defaults (`rule_defaults()` returns `{"round_time": 40}`), and add its own
with `rule_defs()`:

```gdscript
func rule_defs() -> Array:
	return [
		{"key": "lives", "name": "Lives", "default": 3, "min": 1, "max": 9, "info": "Shown in the menu."},
		{"key": "sudden", "name": "Sudden death", "default": false},
		{"key": "ends", "name": "Ends", "default": "rounds", "choices": [["rounds", "After rounds"], ["score", "At a score"]]},
		{"key": "rounds", "name": "Rounds", "default": 5, "min": 1, "max": 20, "when": {"ends": "rounds"}},
	]
```

Read them with `Party.rule("lives")`.

**A whole different party.** With `custom_flow = true` the mode runs the party
itself instead of the card box:

- `party_started(session)`: a new party; change `Party.session` as you like
  (`session.arena` is the first scene, which can be a scene of your mod).
- `start_level(ctl)`: an arena is loaded. Set `ctl.runners` (who races; the
  others watch), then `ctl.place_cards({slot: [item ids]})` (each player places
  those, one after another; the race starts when all are placed).
- `score_round(ctl, gains)`: change the points (they can be negative).
- `after_score(ctl)`: return `true` to decide what comes next yourself (another
  scene with `Transition.change_scene`, or `Party.end_game(message)`).
- `goal_text()` and `score_goal()`: the scoreboard's heading and its bars' scale.

[Auction](https://github.com/AnCarsenat/bot-party-auction) does all of this:
everyone gets a level of their own, items are sold in an auction room (a scene
of the mod), and the levels are raced one after another.

### Looks

Things players wear, chosen per player in **Mods > Looks**:

```json
"cosmetics": {
  "top_hat": { "name": "Top hat", "picture": "top_hat.png", "slot": "head", "offset": [0, -8] },
  "sunglasses": { "name": "Sunglasses", "picture": "sunglasses.png", "slot": "face" }
}
```

Pictures are 32x32, drawn over the robot (same size and place as its body).
`"head"` stays put, `"face"` moves with the eyes. `offset` moves it, in pixels
of the picture. The look's id is `<mod>.<name>` with `-` for `_`: `hats.top-hat`.

### Textures

`"textures"` maps a game texture to a picture in your mod folder:

```json
"textures": {
  "party/art/saw.webp": "red_saw.png",
  "player/player_body.webp": "body.png"
}
```

Keep the same size as the original (most sprites are 32x32, drawn at 2x).
Texture changes show up after restarting the game.

## Online

To join an online game, you need every mod with **items, modes or looks** the
host has switched on, and every **mod pack with maps**, with the same version.
If you're missing some, the host offers to send them: say yes and they're
downloaded and on for that game only (they're kept in `mods_net/`, apart from
your own mods, and switched off when you leave). Raise `version` in `mod.json` when you
share a new version. Map files from mod folders travel with the game, and
textures are only looks, so mod folders with just maps or textures are never
needed by other players.

**Only install mods you trust.** Mods run their scripts like the game's own.
Bot Party always asks before downloading one.

## Sharing on Explore

**Mods > Explore** lists GitHub repositories with the topic `bot-party-mod`. To
be listed:

1. Put your mod folder's files at the root of a GitHub repository (call it
   `bot-party-<your mod>`: Explore leaves out the `bot-party-`), and add the
   topic `bot-party-mod` (the gear next to **About** on the repository's page).
2. Make a release with your `<mod id>.pck` attached (only the first `.pck` is
   used). Explore installs the latest release; its downloads count for the
   **Downloads** sort.

The easy way: copy `.github/workflows/pack.yml` from
[bot-party-hats](https://github.com/AnCarsenat/bot-party-hats) and change
`MOD_ID`. Then every tag you push (`git tag v1.1 && git push origin v1.1`) makes
the pack with the game's own packer and publishes the release.

The repository's name, description and stars show in the list.

**Updates.** Players who installed your mod from Explore are told when a newer
release is out (Mods > Update): raise `version` in `mod.json` and make a release
whose tag is that version (`v1.1`). A pack that's already loaded is replaced
when the game restarts, and the game offers to restart.

## Licenses

Your mods are yours: share them under any license you like (or none).

Bot Party's code is under the GNU GPL version 3 ([LICENSE](LICENSE)), and mods
use it (their scripts extend the game's classes). So that this never gets in
your way, the code comes with an **additional permission**, under section 7 of
the GPL:

> As an additional permission under section 7 of the GNU GPL version 3, the
> copyright holders of Bot Party's code allow **mods** (content the game loads
> at run time from the player's mods folder or from a `.pck` mod pack: scripts,
> scenes, maps, images, sounds, `mod.json`) to be made and distributed under
> any license their authors choose, even though they use or extend Bot Party's
> code and classes. This permission doesn't cover files copied from Bot Party
> into a mod: those keep their own licenses (code: GPL; art: CC BY-NC-SA 4.0,
> see [ASSETS-LICENSE.md](ASSETS-LICENSE.md)).

If your mod reuses Bot Party's art (a sprite, a texture), that part follows the
art license: credit "Bot Party by AnCarsenat", non-commercial, same license.
The name "Bot Party" and its logo are not licensed: call your mod "a mod for
Bot Party", not "Bot Party".

## When something's wrong

The Mods screen shows problems under the mod's name: broken JSON, a missing file,
an item whose scene doesn't exist. Items with problems are left out. Errors from
your scripts show in the terminal when the game is run from a terminal, or in
Godot's output panel.
