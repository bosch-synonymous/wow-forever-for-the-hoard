# For the Hoard

**For the Hoard** adds colour and flexible window placement to WoW Forever's native bags and personal bank.

Designed for **WoW Forever**. No additional addons are required.

Open settings with `/fth`, or select **For the Hoard** under **AddOns** in the game's options.

## Dear Blizzard, all my bag icons are the same

Choose a colour for each bag in your bag bar or bank, display slots with a background tint, individual slot outline, or whole-bag outline.

## What do Blizzard have against moving bag windows?

Drag the combined backpack, individual bags or bank by title bars like nature intended.

## Sometimes I don't want to show ALL my bags at once

Shift-left-click a bag in the bag bar to open it.

## Getting started

1.  Install the packaged add on from CurseForge.For manual installation, place `ForTheHoard` in your Forever client's `Interface/AddOns` folder
2.  Restart the client after adding the add on and enable **For the Hoard**.
3.  Type `/fth` to open settings, or select **For the Hoard** under **AddOns** in the game's options.

Appearance settings are shared across your account; window positions are saved per character.

*   `/fth resetbags` restores automatic placement for the individual backpack, equipped bags and reagent bag.
*   `/fth reset` resets all remembered bag and bank window positions.

When updating, replace the addon folder.

## Compatibility & Issue Reporting

For the Hoard customises the game's native bags and personal bank. It's unlikely to be compatible with addons that replace those windows (eg, Bagnon or BetterBags). This is just a little addon to reflect my personal preferences, and not intended to be a replacement for those.

Please report issues in the project comments with your addon version, other installed addons and their versions, client build, whether combined bags were enabled, steps to reproduce and any error text.

[CurseForge project and downloads](https://www.curseforge.com/wow/addons/for-the-hoard) · [Player guide](src/ForTheHoard/README.md) · [Changelog](CHANGELOG.md)

## Development

Requires Python 3.10 or newer.

```powershell
python -m pip install --target scratch/toolchain/python lupa==2.6
python tests/run_lua.py
python -B -m unittest discover -s tests -p "test_*.py"
python tools/build_release.py
```

The addon ZIP is written to `scratch/dist/`.

By **bosch-synonymous** · [MIT License](LICENSE).
