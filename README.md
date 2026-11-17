# GuildSweep

Opt-in World of Warcraft addon that deposits a chosen amount of your loose money into the guild bank when you open it. Built for WoW Forever (Interface 16001).

## How it works

On first login a setup window asks you to pick one level:

| Mode | Deposits each time you open the guild bank |
|---|---|
| All my copper | Your copper coins |
| Half my silver + all my copper | Half your silver coins plus copper, **once per day** |
| All my silver + copper | Your silver and copper coins |
| Fixed gold amount | The gold amount you set (**max 100g**), **once per day** |

- Nothing happens until you pick a level and click Save.
- Gold mode asks you to confirm before it saves.
- If you have less gold than your chosen amount, it asks before depositing what you have.
- The daily limit is shared across modes, so switching modes does not allow a second deposit the same day.
- It only touches your own character, only when you open the guild bank, and prints a message to your own chat window.

## Commands

- `/guildsweep` opens or closes the settings window.
- `/guildsweep debug` toggles debug output.

## Install

Copy the `GuildSweep` folder into your client's `Interface/AddOns/` directory, then `/reload` or restart the game.

## Status

Early version. Report problems on the issue tracker.
