# Bot Party

A co-op puzzle platformer and party game for 1 to 8 little robots, made with
[Godot 4](https://godotengine.org). Play on one keyboard, with gamepads, online,
or against bots.

![Main menu](docs/screenshots/menu.png)

| Campaign | Party |
|---|---|
| ![Campaign](docs/screenshots/campaign.png) | ![Party](docs/screenshots/party.png) |

- **Campaign:** levels built around buttons, doors, crates and lifts that only
  work if you help each other. The set of levels changes with the number of players.
- **Party:** each round, everyone picks an item (saws, crossbows, fans, ferris
  wheels, paper planes...), places it on the course, then races to the flag.
  Reach the flag where the others can't, and score with the traps you placed.
  Now and then a **Special crate** turns up with one of 14 special items: bear
  traps, punching gloves, magnets, balloons, a hydrogen bomb, a black hole...
  Every box has at least one item that helps and one trap. Rules, game modes and
  item odds can all be changed.
- **Online:** host a game for your friends, or find one on the server list.
  Several people can play on each computer.
- **Bots** to play against, from easy to hard.
- **Map editor** for party arenas, and **mods** for new items, maps, textures,
  game modes and looks (hats!). Find them in **Mods → Explore**; online, the host
  sends the mods you're missing.

## Install

The game is built for Linux, Windows and macOS on every change. **Latest
release** is the recommended version; **nightly** is the newest build, for testing.

**Linux and macOS**, in a terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.sh | bash
```

**Windows**, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.ps1 | iex
```

Run the same command again to update. Until the first tagged release exists, add
the nightly option below. For the nightly build, or to remove the game:

```sh
curl -fsSL https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.sh | bash -s -- --nightly
curl -fsSL https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.sh | bash -s -- --uninstall
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.ps1))) -Nightly
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.ps1))) -Uninstall
```

| | Installed in | Start it from |
|---|---|---|
| Linux | `~/.local/share/bot-party` | the applications menu, or `bot-party` |
| macOS | `~/Applications/Bot Party.app` | Launchpad or Finder |
| Windows | `%LOCALAPPDATA%\BotParty` | the Start menu or the desktop |

You can also download a zip from the
[Releases page](https://github.com/AnCarsenat/bot-party/releases) and run the
game from it. The macOS app isn't signed by Apple: if you open the zip yourself,
right-click the app and choose **Open** the first time.

## Playing

Join from **Players** (press your jump key), then pick **Campaign** or **Party**.

| Player | Move | Jump | Turn | Flip |
|---|---|---|---|---|
| P1 | W A S D | Space | E | R |
| P2 | Arrows | Shift | Ctrl | Enter |
| P3 | I J K L | N | U | O |
| P4 | Numpad 8 4 5 6 | Numpad 0 | Numpad Enter | Numpad + |
| P5 | T F G H | V | B | Y |
| Gamepads | Stick or D-pad | Bottom button | Left button | Top button |

Keys are given by position, so on an AZERTY keyboard P1 plays with Z Q S D.
**Settings → Controls** changes any player's keys. If keys stop responding when
several people share a keyboard, the keyboard can't register that many keys at
once: give each player keys that are further apart.

Plug in as many **gamepads** as you like (Xbox, PlayStation, Switch Pro
controllers, Joy-Cons...). A pad takes a free player when you press one of its
buttons (P6, P7, P8 first, then P5, P4...); **Settings → Controls → Gamepads**
changes who it plays. Buttons go by position: jump is the bottom one (A on Xbox,
B on Switch, Cross on PlayStation).

Turn and Flip rotate and mirror items while you place them in party mode.

- **Players:** jump to join or leave. Choose a slot with the arrows (or the
  mouse): **Delete** removes whoever is in it, even if their keys or gamepad are
  gone, and **+** (or Insert) puts a bot in a free slot, or changes how good a
  bot is. Each player's turn key also removes, and their flip key adds a bot.
- **Bots** play in party mode, shown as B1, B2... Each bot can be Easy, Normal or
  Hard, takes about as long as a person to pick an item, and gets a way of playing
  for each party (normal, trapper, builder or chaos).
- **Party rules:** **Party → Rules** sets the game mode, the winning score, the
  round time, coins, surprise rules, how often Special crates show up, and item
  odds. **Party → Items** turns items on and off, special ones included.
- **Settings → Screen shake** turns off the shake of explosions.
- **Console:** ² or F1 (`help` lists the commands). It has cheats, `keys` (shows
  which keys the game receives), `savestate` / `loadstate`, and `inspect` (an
  in-game node and property editor).

## Online

- **Host public game:** your game appears on the server list, and friends join
  from **Server list**. If they can't reach you directly, the connection goes
  through the server's relay.
- **Host private game:** friends use **Join by address** with your IP. They need
  to reach UDP port 7777 on your computer: forward it on your router, or be on
  the same network. **Online → Port** changes the port.

The default server list is set in `project.godot` (`[bot_party]
online/server_list`). The server is a small Python script in `server/`, and
[server/DEPLOY.md](server/DEPLOY.md) explains how to run it on a VPS.

### Command line

Options go after `--`. For example, to host a party with nobody playing on the
host, starting when two players are in:

```sh
bot-party -- --host --public --port=7777 --players=0 --wait=2 --party
bot-party -- --join=203.0.113.5:7777
bot-party -- --help
```

## Making maps and mods

- **Map editor:** **Party → Map editor**. Draw ground as polygons, add planks,
  the start area, the flag and party items, with grid and object snapping. Draw
  the map's bounds yourself (B) or leave them automatic. Copy, cut, paste and
  mirror (H) what's selected. Test the map straight from the editor. Saved maps
  appear in **Party → Arena**, with a picture of each.
- **In Godot:** open `editor/arena_template.tscn` and edit it with Godot's own
  tools. Press **Save map**, or press F6 to play it.
- **Mods** add items, maps, textures and game modes. Make them in Godot with
  `editor/mod_kit.tscn`: your scenes and scripts become a mod pack (`.pck`) that
  players install from **Mods** (Explore or Browse) and switch on there. Map
  scenes in a pack can hold any Godot nodes. See [MODDING.md](MODDING.md) and the
  example in `mods/example` (its pack is on the Releases page), and the
  [Hats](https://github.com/AnCarsenat/bot-party-hats) and
  [Auction](https://github.com/AnCarsenat/bot-party-auction) mods.

![Map editor](docs/screenshots/editor.png)

## Working on the game

1. Install [Godot 4.7](https://godotengine.org/download).
2. Clone the repository and open `project.godot`.
3. Press F5.

| Folder | What's in it |
|---|---|
| `core/` | game state, camera, transitions, keys, save states, command line |
| `player/` | the robot |
| `objects/`, `logic/` | campaign machines: buttons, doors, lifts, logic gates |
| `levels/` | campaign levels |
| `party/` | party mode: rounds, items, arenas, bots, map format, game modes |
| `editor/` | map editor, the Godot map template, the mod kit |
| `net/` | online play (host-authoritative, with a relay) |
| `mods/` | mod loader, and mods being made (the example) |
| `ui/` | menus, console, inspector, fonts |
| `server/` | server list and relay (Python), VPS deploy scripts |

Every push to `main` builds the game and updates the nightly release. Pushing a
`v*` tag makes a release. See [BUILDING.md](BUILDING.md).

## License

- **Code**: [GNU GPL version 3](LICENSE) (or any later version), with an extra
  permission for mods. You can study, change and share it; versions you share
  must stay under the GPL, with their source.
- **Art** (images, sounds): [CC BY-NC-SA 4.0](ASSETS-LICENSE.md): share and
  remix them with credit, not commercially, under the same license.
- **The name "Bot Party" and its logo**: all rights reserved. Forks are welcome
  under another name.
- **Mods** you make are yours: see [MODDING.md](MODDING.md#licenses).

Want to help? See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

- Game by AnCarsenat.
- Made with [Godot Engine](https://godotengine.org) (MIT license).
- Fonts: [Jersey 10 and Jersey 15](https://github.com/scfried/soft-type-jersey)
  by The Soft Type Project Authors, under the SIL Open Font License. See
  `ui/fonts/`.
- More in [CREDITS.md](CREDITS.md).
