# Courier recovery blocks market connection at startup

Created 2026-11-16. Status fixed in source, regression harnesses passed, live server retest pending.

Related features are [courier delivery](../features/wallet-courier-delivery.md) and
[wallet entity persistence](../features/wallet-entity-persistence.md).

## Symptom and verified cause

The wallet balance refreshed successfully, but opening a market channel produced
the translated storage-failure reply and repeated connection attempts failed.
The local `C:/Users/ricar/Zomboid/server-console.txt` records a startup exception
at `CourierService.lua:277` in `recoverPickups`, followed by
`[ApocWallet/Entities] OPERATION_FAILED Object tried to call nil in recoverPickups`.
Later market requests report `PERSISTENCE_NOT_READY`.

The courier polling removal introduced `next(recoveryOwners)` to detect an empty
pending-recovery set. The deployed Lua environment has no `next` global. The
exception propagated through `EntityStore.run`, whose existing failure handling
blocked the shared store. `MarketTune` then failed admission and returned
`STORAGE`, which the UI translated into its retry message. Balance requests use
the independent API service and could still succeed.

## Correction

`CourierService.lua` maintains a count of unique pending recovery owners. It
increments that count when building the recovery set and decrements it after
successful reconciliation. The zero-owner path returns without calling `next`.
The client polling removal and location-scoped flight events remain implemented.

## Verification and deployment

Disabling `next` in the original courier harness reproduced the failure at the
same production source line. Both courier and entity-store fixtures now run with
`next=nil`. The entity-store harness also executes courier startup through the
real queue and verifies that a subsequent market operation is admitted.

Commands use `npm exec --yes --package=fengari-node-cli -- fengari
tests/<suite>.lua`. Results with mocked engine boundaries were courier 49 checks,
entity store 23 + 41, market 96, market client 46, and courier client 24. All passed.
`pzstudio build` passed. The built wallet `CourierService.lua` matches the source
SHA256 in `C:/Users/ricar/Zomboid/Workshop/ApocalipseBR - Extraction Map Utils`.
`git diff --check` passed.

Install the corrected server Lua and restart the server to initialize a fresh
entity store. The already blocked in-memory store remains blocked until restart.
Live validation must confirm startup without the courier exception and a
successful market channel connection. No live server restart was performed.
