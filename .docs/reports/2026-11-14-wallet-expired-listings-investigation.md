# Missing expired wallet listings

Investigated 2026-11-14 against ExtractionMapUtils revision `832fdbd` and the
existing working tree. Local Java bridge sources are from patches `42.22.2`.
Production deployment versions and affected database rows were unavailable.
Related contracts are [player market](../features/wallet-player-market.md) and
[entity persistence](../features/wallet-entity-persistence.md).

## Confirmed source behavior

- `MarketService.lua` assigns 48 real hours when custody becomes an open listing.
  `update()` expires open listings every 500 ms. `page()` also expires them before
  selecting rows. Both paths operate without a purchase transaction.
- `expire()` changes the listing state and runtime indexes and persists the
  listing. Its units and native item blobs remain present. There is no listing
  or escrow deletion in the expiry path.
- `page()` requires an expired listing, at least one `available` unit, and an
  exact seller character UUID match. `manage()` enforces the same ownership.
  Matching username or Steam ID alone grants no access.
- `MarketClient.page()` carries the current query between modes. A search from
  Mercado or Mochila can therefore hide entries in Meus expirados. Clear search
  and refresh to inspect all pages.
- `MarketPanel.populate()` displays item code, quantity and price. Although the
  server sends `expiresAt`, the panel currently renders no deadline/countdown.
  This is a separate presentation limitation if a report concerns the time label.

## Reproduced initialization defect

`EntityStore.bootstrap()` reconstructs only collections with persisted records.
Empty collections have no rows and are absent after a SQL reload.
`MarketService.data()` supplies its canonical empty tables only when the entire
`d.market` table is absent. An existing market containing listings therefore
skips those defaults.

Before rebuilding the expired index, initialization iterates
`d.market.transactions` and `d.market.credits` unconditionally. Reproductions
using sparse tables matching the loader's output produced these errors.

```text
No purchase records after SQL reload
MarketService.lua:18: bad argument #1 to 'for iterator' (table expected, got nil)

Purchase records with no seller credits after SQL reload
MarketService.lua:19: bad argument #1 to 'for iterator' (table expected, got nil)
```

The first fixture contained `seq`, `listings` and `requests`. The second also
contained `transactions` and omitted `credits`. Neither supplied runtime indexes.
This explains a dependency on prior purchase/sale activity at the document scope.
It does not establish that every individual unsold listing triggers this failure.
A scope containing earlier transaction and credit records already has those tables.

The normal controller submits `Market.update()` through `Store.run()`. An error
in that coroutine makes `EntityStore.resume()` block the store and reject queued
work. A command encountering the error receives `STORAGE`. The failing index
initialization performs no listing deletion or SQL mutation. Its records remain
available for inspection even though the wallet has stopped processing.

The subsequent [unsold-listing hotfix](../hotfixes/wallet-unsold-listing-expiry.md)
initializes `seq`, `listings`, `requests`, `transactions` and `credits`
individually before queue reconstruction. Its regression results and deployment
steps are recorded in the hotfix document. The errors above describe the
investigated code before that correction.

## Character changes

The same Steam ID and username with a replacement character UUID cannot browse
or recover the original character's expired listings. The added market test
reproduces this and verifies that the stock stays `available`.

`ApocBRModEntities.character()` obtains the authoritative UUID from
`ApocBRPlayerRelationalMutations.entityContext()`. The local
`ApocBRPlayerRelationalSync.offerCreatedPlayer()` assigns a random UUID for a new
character. This makes death followed by a new character a concrete candidate
for missing entries. The reports have not been correlated with player deaths.

## Database inspection and recovery

Current persistence uses `mod_data.entity_document_record`, document
`ApocWallet.Couriers.v2`, collection `market.listings`. Each payload wraps its
listing in `value`. Records are scoped by server ID and world. The original
pickup blobs also remain in the associated `escrow` record. V50 wallet tables
are historical archives after V54 and can omit later activity.

The following read-only query locates an account's listings across scopes,
counts unit states and reports purchase activity. Replace the Steam ID literal.
It returns metadata and blob counts, keeping native blobs out of the output.

```sql
WITH listings AS (
    SELECT server_id, world, document_id, record_id, payload->'value' AS listing
    FROM mod_data.entity_document_record
    WHERE document_id = 'ApocWallet.Couriers.v2'
      AND collection = 'market.listings'
      AND payload#>>'{value,seller,steamId}' = 'REPLACE_WITH_STEAM_ID'
)
SELECT l.server_id, l.world, l.record_id,
       l.listing->>'owner' AS owner,
       l.listing#>>'{seller,characterId}' AS seller_character_id,
       l.listing->>'type' AS item_type,
       l.listing->>'state' AS listing_state,
       to_timestamp((l.listing->>'expiresAt')::numeric / 1000) AS expires_at,
       l.listing->>'escrow' AS escrow_record_id,
       units.*,
       (SELECT count(*)
        FROM mod_data.entity_document_record t
        WHERE t.server_id = l.server_id AND t.world = l.world
          AND t.document_id = l.document_id
          AND t.collection = 'market.transactions'
          AND t.payload#>>'{value,listingId}' = l.record_id
       ) AS purchase_transactions
FROM listings l
CROSS JOIN LATERAL (
    SELECT count(*) FILTER (WHERE u->>'state' = 'available') AS available,
           count(*) FILTER (WHERE u->>'state' = 'reserved') AS reserved,
           count(*) FILTER (WHERE u->>'state' = 'sold') AS sold,
           count(*) FILTER (WHERE u->>'state' = 'returning') AS returning,
           count(*) FILTER (WHERE u->>'state' = 'returned') AS returned,
           count(*) FILTER (
               WHERE u->>'state' = 'available' AND length(u->>'blob') > 0
           ) AS available_with_blob
    FROM jsonb_array_elements(
        CASE WHEN jsonb_typeof(l.listing->'units') = 'array'
             THEN l.listing->'units' ELSE '[]'::jsonb END
    ) AS unit(u)
) units
ORDER BY l.server_id, l.world, l.record_id;
```

Expired `available` units with valid blobs are candidates for exact-item recovery.
The existing MarketRecover path queues them through a durable courier receipt
and marks them returned. It requires the original character, working persistence
and no unresolved reserved units. A new character currently has no recovery path
for the old character's listings. Operator-assisted recovery would need a scoped
ownership/custody reconciliation before moving those units.

Check transactions, market actions, courier receipts/jobs and unit states before
recovery. Original escrow also retains sold/returned cargo history, so copying
every escrow blob would duplicate previously fulfilled items. `collecting`,
`interrupted`, `returning` and reserved stock need their respective intent and
delivery state reconciled first. Editing database rows while the server holds
its loaded revision can cause a persistence conflict or stale in-memory state.

## Validation

- Existing market harness passed 70 checks before this investigation.
- Added never-purchased two-unit expiry, expired-index reconstruction, search
  hiding, replacement-character access denial and original-character exact-blob
  recovery checks to `tests/wallet-market.lua`. It passed 83 checks.
- `tests/wallet-entity-store.lua` passed its 35 cumulative checks using the real
  store/facade and a simulated asynchronous database transport.
- A temporary copy of the market harness appended the two sparse-load fixtures
  above. Both reproduced the initialization error. The temporary file was removed.
- Commands used `npm exec --yes --package=fengari-node-cli -- fengari` followed
  by the applicable Lua test path. The harness's deliberate persistence-failure
  and conflict messages are expected test output.
- Local decompiled `LuaManager.getTimestampMs()` delegates to
  `System.currentTimeMillis()`, confirming wall-clock expiry.
- No live database query, affected-player identification, dedicated-server test,
  deployment, runtime hotfix or production item recovery was performed. The SQL
  above was reviewed against the local record-load contract and was not executed.
