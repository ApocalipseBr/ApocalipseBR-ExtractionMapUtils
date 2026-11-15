# Unsold listing expiry after database reload

Status implemented and validated in Lua harnesses on 2026-11-14. Dedicated-server
and client validation remains pending. Related documents are the
[investigation](../reports/2026-11-14-wallet-expired-listings-investigation.md),
[market lifecycle](../features/wallet-player-market.md) and
[record persistence](../features/wallet-entity-persistence.md).

## Symptom and cause

A server/world with listings and no purchase history could stop processing the
wallet after a reload. The record loader creates collections only for rows it
receives. Empty transaction and seller-credit collections are therefore absent.
Market initialization assumed both tables existed when reconstructing queues,
raising an error that blocked the persistence worker before expired stock could
be browsed. Transaction history with no credit records triggered the same issue.

Expiry retains listing records and native item blobs. This failure prevents
processing and presentation of retained stock.

## Change

`MarketService.data()` now initializes each canonical collection and the sequence
counter independently before reconstructing indexes. Existing values survive.
Expired rows continue to be selected by listing state, available units and seller
character UUID. Buyer transactions are unnecessary for that selection.

This allows existing unsold stock to expire, appear in Meus expirados and pass
through the existing recovery/repost flow after a cold load. Recovery preserves
the original item blobs and durable courier receipt behavior.

## Validation

The market regression was run before the fix and reproduced initialization
errors for missing transaction and credit tables. After the fix these commands
passed from the repository root.

```powershell
npm exec --yes --package=fengari-node-cli -- fengari tests/wallet-market.lua
npm exec --yes --package=fengari-node-cli -- fengari tests/wallet-entity-store.lua
```

- Market harness passed 85 checks, including sparse canonical data with no
  purchases, expired-page visibility, exact-item recovery and transactions with
  no seller-credit history.
- Entity-store harness passed 40 cumulative checks. The new fixture persists an
  unsold open listing through the real store/facade, reloads its records through
  the simulated asynchronous database transport, expires it through the queued
  market update, acknowledges the mutation and checks the stored expired state,
  runtime expired index and retained blob.

The harness deliberately logs persistence failures and a conflict in existing
negative cases. Those messages accompany successful completion.

Deploy the updated wallet and restart the server to reload canonical state and
rebuild indexes. A store already blocked by the old error requires that restart.
The production database and affected accounts were not inspected. Character UUID
ownership and name search continue to affect visibility as described in the
investigation. In-game validation should include Meus expirados, recovery and
reposting for an existing unsold listing after restart.
