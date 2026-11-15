# Wallet context menus at the cursor

Status: implemented; awaiting in-game validation. Date: 2026-11-15.

The radio Menu button opened its options at the window's top-left corner,
away from the clicked key. `ApocWallet/UI/MarketPanel.lua` passed the window
coordinates to `ISContextMenu.get` for both Menu and expired-stock management.
Both calls now use `getMouseX()` and `getMouseY()` while preserving the player
index and menu actions.

This follows local vanilla `media/lua/client/ISUI/ISInventoryPage.lua` and
`ISEquippedItem.lua`. The exposed mouse globals were verified in decompiled
`zombie/Lua/LuaManager.java`; vanilla `ISContextMenu.get` stores the requested
screen coordinates and retains its native animation and edge handling.

Affected feature: [player market and radio operator](../features/wallet-player-market.md).

Validation: `tests/wallet-market-client.lua` captures menu coordinates and checks
the Menu anchor away from the window origin, then moves the simulated cursor
and checks the expired-stock actions anchor. Existing option/action checks remain.

Commands and results:

- `npm exec --yes --package=fengari-node-cli -- fengari tests/wallet-market-client.lua`: passed, 46 checks.
- `git diff --check`: passed.

Tests mock native widgets. Visual placement, native edge adjustment and focus
still require a Build 42 client check. No deployment was performed.
