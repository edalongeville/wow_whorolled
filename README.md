# WhoRolled

A World of Warcraft addon (Interface 16001, WoW: Forever client) that shows who chose Need, Greed or Pass on each loot roll, and keeps a history of past rolls. Standalone: no dependency on any other addon, nothing uploaded.

The addon is still being tested.

## Features

- A panel to the right of each loot roll frame: every player in their class colour with their choice (Besoin / Cupidité / Passer, or Need / Greed / Pass on an English client), their roll once it is known, a check mark on the winner, and how many players have not chosen yet
- A history window (`/whorolled history`): one line per item with its winner and boss, then the choices grouped by type. Hover an item for its tooltip, shift-click to link it in chat. Movable, resizable, closes with Escape; keeps the last 200 items
- Roll data comes from the client's loot history (`C_LootHistory`). If that turns out to be empty, `/whorolled source chat` reads the loot chat messages instead, matched against the client's own localized strings (works on French and English clients)
- The loot roll frames can be moved anywhere with `/whorolled move`, and stay there
- `/whorolled test` plays a fake roll to check the display without a dungeon, `/whorolled test 5` five at once

## Options

Everything is in an options page: **Options -> AddOns -> WhoRolled**, `/whorolled`, or the game's add-on menu (the numbered icon by the minimap: left click for the options, right click for the history). It has the panel toggle, Move / Reset position / Test roll / Test roll x5 buttons, the history (open, number of items kept, clear), the roll data source and debug messages.

## Commands

The same things are available as commands, `/whorolled` (or `/wroll`):

| Command | Effect |
|---|---|
| `/whorolled` | open the options |
| `/whorolled history` | show or hide the history |
| `/whorolled test [1-10]` | play fake rolls, one by default (`/whorolled test 5`: five at once, stacked like real rolls) |
| `/whorolled move` | show a green anchor to drag the loot roll frames (and their panels) anywhere; close it (X) to lock. The position is saved |
| `/whorolled reset` | give the loot roll position back to the game (after a `/reload`) |
| `/whorolled attach` | toggle the panels next to roll frames |
| `/whorolled source auto\|api\|chat` | where roll data comes from (`auto`: the loot history API when the client has it) |
| `/whorolled status` | diagnostic info (client build, API present, source in use, active rolls) |
| `/whorolled debug` | print each loot event in the chat |
| `/whorolled clear` | erase the history |

## Layout

| Path | Content |
|---|---|
| `WhoRolled/` | the addon: `Locales.lua` (strings), `Core.lua` (data, events, chat parsing, slash commands), `UI.lua` (roll frame panels, roll position, history window, test mode), `Options.lua` (options page), `.toc` |
| `spec/` | [busted](https://lunarmodules.github.io/busted/) tests, run against a stubbed WoW API (`spec/helpers.lua`) |
| `tools/` | `check.sh`, the same checks as the CI |
| `.luacheckrc` | luacheck configuration (Lua 5.1, WoW globals) |

## Development

Lua 5.1, as in the WoW client.

```bash
tools/check.sh
```

`tools/check.sh` runs what the CI runs (luacheck, then the busted specs) and installs the Lua tooling first with apt if it is missing (`--no-install` to only check). Without the script: `luacheck . && busted --lua=lua5.1 spec`.

Bump `## Version` in `WhoRolled/WhoRolled.toc` with every change to the addon (patch for fixes, minor for features); the CI fails a pull request that changes `WhoRolled/` without a bump.

To release, run **Actions -> Release -> Run workflow** on main: it releases the `## Version` already committed in the `.toc` (nothing to choose), fails if that version has already been released, and publishes the zip as a GitHub release. "Dry run" only checks and tests. There is no CurseForge upload yet; `.github/workflows/release.yml` says how to add it.

## Disclaimer

This is a personal project, and its real purpose is to experiment with AI-assisted coding. The WoW addon is mostly a harmless playground for that: small, low-stakes and easy to test. It was built with AI on purpose, and that's the point of it. Use it if it's useful to you; if it isn't, no hard feelings.

## License

[MIT](LICENSE)
