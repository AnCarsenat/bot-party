# Making mods for Bot Party

A mod is a folder with a `mod.json` file. Put it in the game's mods folder and it
shows up in **Settings > Mods**, where each mod can be switched on and off.

A mod can:

- **add party items**: built-in item scenes with new settings, a script, or both;
- **add maps** for party mode (made with the map editor);
- **replace textures** (any sprite in the game).

A complete example lives in [`mods/example/`](mods/example). It adds a pinball
bumper, a long plank, a mint coin and a map. Copy that folder into your mods
folder to try it, then change it.

## Where mods go

**Settings > Mods > Open mods folder** opens the folder. Depending on your system,
it's here:

| System  | Folder |
|---------|--------|
| Linux   | `~/.local/share/godot/app_userdata/Bot Party/mods/` |
| Windows | `%APPDATA%\Godot\app_userdata\Bot Party\mods\` |
| macOS   | `~/Library/Application Support/Godot/app_userdata/Bot Party/mods/` |

Give each mod its own folder:

```
mods/
  my-mod/
    mod.json
    rocket.png
    rocket.gd
    maps/
      long-jump.json
```

The folder name is the mod's id (lower case, `-` for spaces). Item ids get it
as a prefix: item `rocket` in folder `my-mod` is `my-mod.rocket` (that's the name
to use with the console: `give my-mod.rocket 1`).

## mod.json

```json
{
  "name": "My mod",
  "author": "You",
  "version": "1.0",
  "description": "One line shown in the Mods screen.",

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

### Items

| Key | What it does |
|-----|--------------|
| `name` | Name on the pick card and in Party > Items. |
| `scene` | The item's scene. Use a game scene (`res://...`, list below) or a `.tscn` in your mod folder. |
| `script` | A `.gd` file in your mod folder, added to the item (see below). |
| `icon` | Picture on the pick card: a png in your mod folder, or a game texture (`res://...`). |
| `size` | `[width, height]` of the item in pixels. Used to stop building in the start and flag areas. |
| `offset` | Where that box sits from the item's centre, `[x, y]`. |
| `weight` | How often it shows up, 0 to 20. Built-in items use 5 to 10. Players can change it in Party > Items. |
| `props` | Properties set on the scene's root node, for example `"modulate": "#ff8080"` or `"one_way": true`. `[x, y]` becomes a Vector2 and `"#rrggbb"` a Color. |
| `host` | `true` if other items can hang from it (it needs a `mounts()` method, like the ferris wheel). |
| `bomb` | `true` for a bomb: it has no scene and destroys items within `radius` pixels. |

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

- `Mods.texture(path)`: loads a png, jpg or webp from your mod folder.
- Players are `CharacterBody2D` on physics layer 2 (mask `2` to detect them).
  - `player.bounce(speed, 1.0, direction)` launches a player, like a trampoline.
  - `player.velocity` is the player's velocity.
- To hurt players, add a `Hazard` (`res://party/hazard.gd`, an Area2D):
  touching it takes the player out, and the item's owner gets the trap points.
- `Party.session` holds the round, scores and placed items.

Pngs can't go in a `.tscn` inside your mod (Godot only imports the game's own
files). Load pictures with `Mods.texture()` from the script instead, like the
bumper does.

**Only install mods you trust.** Scripts can do anything a game can. Bot Party
never downloads scripts: in online games everybody needs the mod installed.

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

Saved maps go to `maps/` next to `mods/`. In Godot, you can also set
`save_folder` to save straight into your mod. Copy the `.json` files into
your mod's `maps` folder. They show up in **Party > Arena**, marked "(mod)".

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

To join an online game, you need every **item** mod the host has switched on,
with the same version. Otherwise the game says which mods are missing. Maps
travel with the game, and textures are only looks, so mods with just maps or
textures are never needed by other players.

## When something's wrong

The Mods screen shows problems under the mod's name: broken JSON, a missing file,
an item whose scene doesn't exist. Items with problems are left out. Errors from
your scripts show in the terminal when the game is run from a terminal, or in
Godot's output panel.
