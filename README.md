# Reckless Stat Tracker

A small World of Warcraft (Retail) addon that shows one icon with:

- how many **Potion of Recklessness** (or any potion you choose) are in your bags
- the potion's **cooldown** spiral
- your current **highest secondary stat** (Crit / Haste / Mastery / Versatility), color coded, with the rating number if you want it

## Install

1. Download this repository (green **Code** button → **Download ZIP**) and unzip it.
2. Put the folder in `World of Warcraft\_retail_\Interface\AddOns\` and name it exactly `RecklessStatTracker`
   (so the path is `...\AddOns\RecklessStatTracker\RecklessStatTracker.toc`).
3. Restart the game or type `/reload`.

## Settings — minimap button

| On the minimap button | Does |
|---|---|
| Left-click | Open the settings menu |
| Right-click | Lock / unlock the icon position |
| Drag | Move the button around the minimap |

The menu has:

- **Lock position (click-through)** — unlock to drag the icon, lock so clicks pass through it
- **Show stat rating number**
- **Show only in combat** — only applies while the position is locked
- **Show cooldown spiral**
- **Icon scale** — 0.50 to 3.00
- **Tracked item** — pick a potion from your bags, or type any item name
- **Reset position & settings...**
- **Show minimap button**

You can also open the menu by right-clicking the icon while it is unlocked, from the **AddOns** button on the minimap, or with `/reckless`.

## Slash commands

`/reckless` and `/rst` do the same thing.

| Command | Does |
|---|---|
| `/reckless` | Open the settings menu |
| `/reckless minimap` | Show / hide the minimap button |
| `/reckless lock` · `/reckless unlock` | Lock / unlock the icon |
| `/reckless scale 1.2` | Icon scale (0.5 – 3.0) |
| `/reckless num` | Toggle the stat rating number |
| `/reckless combat` | Toggle show only in combat |
| `/reckless cd` | Toggle the cooldown spiral |
| `/reckless item <name>` | Track items whose name contains `<name>` |
| `/reckless reset` | Reset position and settings |
| `/reckless help` | List the commands |

## Notes

- The tracked item is matched by name, so it works for every rank of the same potion.
- The default item name is in English. On a client in another language, pick your potion from **Tracked item** (it lists the potions in your bags by their in-game names).
