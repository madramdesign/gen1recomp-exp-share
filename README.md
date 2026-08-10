# Exp Share (gen1recomp)

Always-on party experience for [gen1recomp](https://github.com/bryanthaboi/gen1recomp).

## Modes (MODS → Exp Share)

| Mode | Behavior |
| --- | --- |
| **MODERN** | Full undivided EXP to every living party Pokémon (Gen 6+). Uses the official `battle.exp_award` hook and the engine's `applyShare` (0.1.39+ / current). |
| **CLASSIC** | Gen 1 **EXP.ALL** math without needing the item |
| **OFF** | Vanilla |

On **0.1.38** (no `awardExp` / hook), the mod forces classic EXP.ALL so sharing still works — you should see “with EXP.ALL” messages for the whole party.

**EXP MESSAGES:** EVERYONE (default) / FIGHTERS / SILENT

## Install

1. Download the release zip or copy this folder to `mods/exp_share/`
2. Enable in **F10** / Start → Mods
3. **Fully quit and relaunch** the game (hooks install on `game.ready`)

## How to verify

1. Put 2+ Pokémon in the party (bench can be low level)
2. Win a wild battle with only the lead fighting
3. You should get EXP text for **bench** mons too (“with EXP.ALL” on older builds; undivided amounts on current builds in MODERN)

## Not the same as

- **Battle EXP Bar** — HUD only
- **Pokewalker** — real-world steps → EXP
- Index `exp_share` from other authors — different mod, same id (disable duplicates)
