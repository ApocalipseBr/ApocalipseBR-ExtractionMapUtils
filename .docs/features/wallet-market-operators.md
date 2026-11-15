# Market operators and server gossip

Status — implemented, awaiting B42 dedicated-server/client validation.

SPARKS (`sparks`, male) uses the sixteen `control_00.png` through
`control_15.png` snapshots. IRON ECHO (`iron_echo`, female) uses the corresponding
`ironcontrol_` snapshots. Both are eligible for uniform random selection and provide
cosmetic identity and dialogue. Their personality is expressed by their PTBR text.

## Contact lifecycle

`server/ApocWallet/Operators.lua` owns definitions, selection rules and an in-memory
contact cache keyed by the trusted character UUID. A successful tune establishes
contact. Market page, posting, buying, recovery and reposting requests refresh
the deadline to ten real minutes after that interaction. The first interaction
at or after the deadline rolls again, including within an existing open window.
Closing the window, changing radio or reconnecting retains an unexpired contact.
A new character has its own contact. Server restart clears all assignments.
An independent cleanup pass releases expired entries every thirty seconds.
Contacts retain operator keys and deadlines without player objects or SQL writes.

Purchase-status polling and courier ETA synchronization leave this deadline
alone. Existing radio authorization, thirty-minute radio-session inactivity,
inventory custody, payment acknowledgment and transaction retry rules still apply.
Radio hangup releases the radio session. The character contact cache owns the
longer-lived operator assignment.

`OperatorRules.lua` is the extension point for server rules. Register definitions
through `Operators.register` with `key`, `name`, `gender`, `texturePrefix` and
`randomEligible`. Names and gender are presentation metadata. Portrait prefixes
identify up to sixteen zero-padded PNG files (`00` through `15`) under
`media/textures/ApocWallet/operator`. One image is sufficient; missing numbers
are skipped. Images can be independent poses rather than animation frames.

Each radio window starts with the first available snapshot and holds it for at
least five seconds. Once the hold expires, operator speech advances to the next
available snapshot in numeric order, wrapping at the end. Silence retains the
current image, so short replies do not trigger rapid cycling or snap back to
the first pose. A long render gap advances at most one image, with a fresh
five-second hold. Changing operators or leaving the connected state resets the
sequence. Texture caching and the existing radio scan-line effect remain.

Snapshot verification (2026-11-15):
`npm exec --yes --package=fengari-node-cli -- fengari tests/wallet-operator-portrait.lua`
passed 15 checks covering timing boundaries, silence, reply progression, sparse
and single-image sets, wraparound, long gaps, caching, independent windows,
operator changes, missing assets and reconnects. The market-client harness also
passes 46 checks. These tests mock rendering; visual pacing awaits in-game validation.

```lua
local Operators=require 'ApocWallet/OperatorRules'
Operators.registerRule('secret-contact',100,function(context)
    if MySecretService.canContact(context.characterId) then return 'my_operator' end
end)
```

Register a definition for `my_operator` before the rule can select it. The rule
context contains server-derived `characterId`, `sourceServerId` and `player`.
Higher priorities run first, with rule key as the deterministic tie-breaker.
Returning an existing operator key selects that operator, including definitions
excluded from random selection. Returning nil continues. Exceptions are logged
and selection continues. With no matching rule, `roll(context)` chooses uniformly
from the sorted random-eligible keys. Rules run when a contact is newly rolled.

## Gossip ownership and database boundary

`GossipController.lua` owns startup loading, validation, in-memory category pools
and final line selection. It uses the existing server-only `ApocBR/Entities`
facade. `OperatorFallbacks.lua` supplies one PTBR line per category per built-in
operator while content is loading or unavailable.

Manager migration `V55__Wallet_Operator_Gossip.sql` creates
`mod_data.wallet_operator_gossip`, with one shared content record per operator.
The primary key is `operator_key`. `enabled` enables database content for that
operator, `pools` is bounded JSON-object text, and `revision` is a positive bigint.
These content records are shared across server/world scopes. Operator eligibility
is configured in Lua. Flyway/backend owns content updates and revision increments.
The game engine role `pz_server_01` receives schema usage and SELECT on the table.

Startup performs one asynchronous keyed `find` per registered operator. Each
record contains all its category arrays. A successful load stays in memory for
the process lifetime. Failed reads retry after thirty seconds with one in-flight
read per operator. Missing or disabled records settle on fallback until restart.
Malformed JSON is retried after thirty seconds. Invalid individual categories
use fallback while valid categories remain available. Startup logs expose load,
failure and missing-record fallback decisions. Steady interaction performs no
gossip database reads or writes. Newly registered operator definitions are also
loaded after startup.

Each built-in operator has ten distinct database lines for each of nineteen
categories, totaling 380 lines. The categories are `greeting`, `page_market`,
`page_inventory`, `page_expired`, `posted`, `reserved`, `bought`, `reposted`,
`recovered`, `error_radio`, `error_signal`, `error_wait`, `error_item`,
`error_sold`, `error_funds`, `error_refused`, `error_storage`, `eta_pickup` and
`eta_delivery`. Name search, clearing search and page navigation use the category
for the requested view. Drone cargo manifests retain their separate drone voice.

Templates support `{operator}`, `{page}`, `{item}`, `{count}` and `{seconds}`.
Greeting templates require operator and page. Page templates require page.
Posting/reservation/completed-purchase templates require item, count and page.
Recovery, reposting and item/sold/funds failures require item and page. General
refusals require page. ETA templates require seconds. Unknown tokens, control
characters, missing mandatory references and lines exceeding the Lua length limit of 1024 are
rejected. Each category contains one to thirty-two entries. Database pools are
bounded at 256 KiB per operator. New operators without their own Lua fallback use
the SPARKS fallback wording with their own name substituted.

Server responses include the selected operator metadata and rendered `gossip`
string. The client queues that string verbatim, preserving the operator name on
each transcript entry when a later contact changes operators. The full pool stays
on the server. Courier ETA packets carry a selected operator line when a market
session exists. Existing ETA deduplication prevents repeated speech during sync.
Unassigned radio/identity errors and local amount validation use PTBR UI text.

## Radio references

`MarketProtocol.pageReference` produces `MER-003` for market page 3, `EXP-003`
for expired stock and `MOC-003` for backpack. Player requests address the current
operator and include the coded bulletin. Posting, buying, recovery and reposting
requests include the cargo code, current view/page and sector. Acknowledgments
derive cargo references from server-owned inventory/listing/transaction data.
The current bulletin reference remains in successful item acknowledgments.

Page chatter remains limited to one exchange per five seconds. Requests marked
`silent` suppress page gossip for fast navigation and automatic refreshes.
Pending purchase polls carry no gossip. Final purchase speech follows confirmed
debit and durable delivery registration. The existing bounded dialogue queue and
1.4-second spacing remain in use.

## Deployment and verification

Apply manager migration V55 through the game-runtime Flyway datasource before
restarting the server with this wallet version. Deploy the wallet Lua and both
portrait sequences to server/client distributions. Existing pack and Java entity
APIs support this mapping. Database content changes take effect after restart.

Focused verification uses the real registry, gossip controller, pack entity facade,
market service and client/UI code with mocked engine boundaries. Run from the mod
repository root with `npm exec --yes --package=fengari-node-cli -- fengari` followed
by `tests/wallet-operators.lua`, `tests/wallet-market.lua`,
`tests/wallet-market-client.lua` or `tests/wallet-entity-store.lua`.
`py tests/wallet-translations.py` validates UI catalogs.

Manager `WalletOperatorGossipMigrationTest` runs the actual Flyway migration on a
disposable PostgreSQL database when `GAME_RUNTIME_TEST_POSTGRES_URL` points to a
local test instance. It checks repeat migration, 380 distinct seeded variations,
required placeholders, malformed content rejection, keyed reads and engine grants.
Run with `.\mvnw.cmd '-Dtest=WalletOperatorGossipMigrationTest' test`.

Verification on 2026-11-15 passed 106 operator/cache checks, 96 market checks,
44 market client checks, 40 entity-store checks, 37 courier checks, 22 courier
client checks and 67 radio UI checks, plus translation catalog validation.
All 380 seed lines also passed the production Lua validator and renderer in a
temporary fixture generated from V55. The four manager migration tests passed
against a disposable PostgreSQL 17.6 cluster using Java 25 and Flyway, including
V50's inherited default grants. `git diff --check` passed for the changes.
Native radio speech, rendering for both portrait sets, reconnect behavior and
queue timing still require a dedicated B42 server and client.
