# Wallet expired-list refresh after repost

Status: implemented; awaiting in-game validation. Updated 2026-11-21.

## Symptom and cause

Reposting succeeded on the server, but the expired listing remained visible.
The operator's final message asked for more time; a manual page refresh showed
the updated state. The client sent its automatic page refresh on the next tick
after acknowledgment. A fast repost could therefore put the refresh inside
`MarketService.handle`'s 300 ms request admission window. The resulting `WAIT`
cleared the pending client request after its refresh flag had already been
consumed, leaving no scheduled refresh. Restore uses the same client path, but
its courier work can change the response timing.

## Fix and affected files

- `ApocalipseBR-Wallet/common/media/lua/client/ApocWallet/MarketClient.lua`:
  automatic refreshes after post, repost, recovery and purchase completion wait
  350 ms after acknowledgment. A marked automatic refresh retains its original
  token and arguments on `WAIT`, retrying after 350 ms without operator chatter.
  User management requests retain their existing error handling; the client
  does not automatically repeat a rejected management action.
- `tests/wallet-market-client.lua`: regression covers the cooldown boundary,
  silent refresh backpressure/retry, preserved expired mode/page/search, removal
  from the rendered expired list, and continued recovery refresh behavior.

Server authority, persistence, admission limits and listing lifetime are
unchanged. See [player market](../features/wallet-player-market.md).

## Validation

Run from the repository root on 2026-11-21:

```powershell
npm exec --yes --package=fengari-node-cli -- fengari tests/wallet-market-client.lua
npm exec --yes --package=fengari-node-cli -- fengari tests/wallet-market.lua
npm exec --yes --package=fengari-node-cli -- fengari tests/wallet-entity-store.lua
npm exec --yes --package=fengari-node-cli -- fengari tests/wallet-radio-ui.lua
git diff --check
```

Client: 57 checks passed; market service: 96; entity store: 41; radio UI: 67.
The new client regression first failed against the original implementation at
the immediate repost-refresh assertion, then passed with the fix. Expected
mock persistence-failure/conflict logs were emitted by the server/store tests.
Diff whitespace checks passed.

These harnesses execute production Lua with mocked engine/network boundaries.
No live server or client was used and no deployment was performed. Verify a
repost from Meus expirados on the actual server: the item should leave that
view automatically and appear in Mercado without manual refresh. Sustained
server backpressure keeps a silent refresh pending until admitted; disconnect
or closing the radio still ends the session through the existing lifecycle.
