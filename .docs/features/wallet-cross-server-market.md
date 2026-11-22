# Cross-server player market

Status: implemented and verified with isolated PostgreSQL, Lua harnesses and
the original game archive. Production rollout and dedicated-server acceptance
remain pending. Updated 2026-11-22.

## Market behavior

All Wallet servers connected to the same `game_runtime` database use one player
market. There is no server allowlist. The radio keeps its existing commands and
views. PostgreSQL filters and paginates the bulletin, and each public listing ID
includes its source server and world. Two worlds can post the same local listing
number without a collision.

The seller's Steam account owns expired stock. This allows the same account to
repost or recover it from another server with a different character. Payouts
retain the seller's original character and server identity. Pickup and delivery
jobs, coordinates, debit intents and receipts remain scoped to the world which
accepted the corresponding action.

## Persistence and recovery

Manager migration `V60__Shared_Wallet_Market.sql` backfills a compact
`mod_data.wallet_market_catalog` projection from the V54 listing records.
The original listing row remains authoritative for item custody. PostgreSQL
maintains the projection in the same transaction as a listing write and serves
six summary rows per page without transferring item blobs to browse. The
engine asynchronously loads a single full record when handling a trade.

The wallet mutation function locks the listing row and compares its observed
checksum before changing it. The listing update and the buyer's local purchase
reservation, or the claimant's local return intent, commit together. A conflict
rolls back both; Wallet returns a retryable response and leaves the local store
ready. Buy reservations recheck the expiration deadline against the database
clock under the row lock. The existing revision and mutation token still make
ambiguous commits replayable. Seller credits use the globally distinct buyer
transaction key and the existing immutable receipts.

Expired stock is projected using PostgreSQL time as soon as its deadline
passes. The authoritative state changes on a buy or manage attempt. Native
world inventory saves still follow the courier's existing recovery rules.

## Cargo compatibility

New cargo records embed the source dictionary namespace, exact view and
native world version. The destination prepares foreign dictionary views
asynchronously, then checks the selected exact items before reserving stock or
accepting a claim. A missing type, missing dictionary or incompatible native
payload leaves stock available. Older untagged stock stays visible and can be
traded locally. Its originating world upgrades it in bounded batches after
checking the expected item type, preserving the native bytes. Other worlds
reject untagged blobs until the origin upgrades them.

## Release

Use a coordinated maintenance window for all Wallet servers. Stop their JVMs,
apply V60 through the manager's game-runtime Flyway datasource, install the
matching Java agent and Wallet mod on all servers, and then restart them.
Keep PostgreSQL dictionary publication and decoding enabled and give each
server its existing unique source ID. The existing pack entity facade forwards
the updated protocol. Old Wallet writers are rejected by V60 when changing
listings, so a mixed-version rollout can interrupt market work.

## Verification

- `npm exec --yes --package=fengari-node-cli -- fengari tests/<name>.lua`
  passed for `wallet-market`, `wallet-entity-store`, `wallet-courier` and
  `wallet-market-client`. Shared tests exercise source payout, destination
  delivery, retry safety and same-account expired recovery with a new character.
- Manager `mvnw -o -Dtest=WalletMutationMigrationTest test` passed ten tests in
  isolated PostgreSQL 17.6 with distinct migration and engine roles. Coverage
  includes backfill, search, paging, expiry, winner selection across two scopes,
  atomic local intent writes and exact mutation replay.
- Agent `mvn "-Dtest=CourierItemCodecTest,DictionaryDecodeTest,LuaHookTest" package`
  passed and built the shaded JAR against the original archive. No production
  deployment or two-dedicated-server delivery test was performed.
