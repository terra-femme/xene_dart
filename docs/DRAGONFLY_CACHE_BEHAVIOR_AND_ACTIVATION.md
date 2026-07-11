# DragonflyDB Cache — Behavior & Activation Guide

**Last verified:** 2026-07-06 (against live Azure + code on branch `feat/perf-cost-fixes`)
**Status (updated 2026-07-07):** Dragonfly is **retired** — scaled to 0 replicas. The app runs fully without it by design. The reconnect loop is **deployed** (PR #63, revision `--0000021`+) and `DRAGONFLY_URL=redis://xene-dragonfly:6379` is **permanently set** (revision `--0000022`, verified in logs 02:17 UTC). **Activation is one command** — see §5; the prerequisite step there is already done.
**Update 2026-07-10:** scaled-to-zero is **not fully dormant** — the reconnect probe briefly wakes it daily via TCP-ingress activation, costing ~$1–2/mo. See §9.

This document is the single source of truth for what the Dragonfly cache
actually does, how the backend behaves with and without it, and exactly how
to turn it back on. It supersedes the performance claims in
`docs/performance/REDIS_DRAGONFLYDB_IMPLEMENTATION.md` (see
"[Myth vs. reality](#myth-vs-reality)" below).

---

## TL;DR

| Question | Answer |
|---|---|
| What does Dragonfly store? | One thing: 10-second `feed_inflight:*` request-coalescing markers. **No feed data, no images, no user data.** |
| Is the app slower without it? | No. Feed speed comes from Supabase `feed_items` + stale-serve + batched prefetch. Backend measured 299ms with Dragonfly off. |
| What degrades without it? | One narrow race: simultaneous *fully-cold* misses across ≥2 replicas → the lease-losing replica returns empty instead of waiting ≤10s for fresh data. |
| Does it auto-reactivate? | *Functionally* no — but see §9: TCP ingress lets the backend's 3-minute probe **briefly activate** the scaled-to-zero replica even with `scaleRules: null`. Verified via `Replicas` metric + billing, 2026-07-10. The **backend client** auto-adopts — since 2026-07-06 it retries every 3 minutes and connects automatically when reachable. |
| When should it come back? | When `xene-backend` routinely holds **≥2 replicas at rest**. Not before. An alert exists for exactly this signal. |
| What did it cost? | $22.54 of the $26.10 June 20 → July 6 bill (1 vCPU / 2 GiB, 24/7) — to hold 10-second strings. |

---

## 1. Architecture: what Dragonfly is in xene

- **Deployment:** Azure Container App `xene-dragonfly` in resource group
  `xene-rg`. TCP ingress (internal), image is Redis-protocol-compatible
  DragonflyDB. Currently `minReplicas: 0`, `maxReplicas: 1`,
  `scaleRules: null` (verified via `az containerapp show`).
- **Client:** `packages/xene_backend/lib/src/services/dragonfly_cache_service.dart`
  — a hand-rolled RESP (Redis protocol) client over `Socket.connect`, 5s
  connect timeout, singleton via factory constructor.
- **Connection string:** `DRAGONFLY_URL` env var on `xene-backend`.
  The verified-working value (from Azure revision history, revisions
  `--0000015` → `--0000017`, live 2026-06-24 → 2026-07-06):

  ```
  redis://xene-dragonfly:6379
  ```

  ⚠️ Use the **short container name** form. The
  `https://xene-dragonfly.internal.yellowwater-....azurecontainerapps.io`
  form was tried during the original June 23 rollout (revisions
  `--0000006` → `--0000011`) and replaced — it does not work for raw
  TCP/RESP (commit `643e3a2`).

## 2. What the code actually uses it for

Exactly **one** functional call site: `packages/xene_backend/lib/src/feed_cache.dart`.

When a feed request needs a **live scrape** (cache miss or hydration), the
fetching replica writes a marker before scraping and deletes it after:

- Key: `feed_inflight:<platform>:<artistName>`
- Value: the string `"fetching"`
- TTL: 10 seconds

Other replicas that want the same artist during those seconds see the marker
(`exists()`) and poll every 100ms for up to 10s, then read the (now-fresh)
rows from Supabase instead of launching a duplicate scrape. That's the whole
job: **cross-replica request coalescing**. The remaining references in the
codebase are dependency wiring (`routes/_middleware.dart`) and the metrics
endpoint (`routes/monitor/cache.dart`).

### Myth vs. reality

`docs/performance/REDIS_DRAGONFLYDB_IMPLEMENTATION.md` (June 22) claims
Dragonfly serves feed data at 2–3ms, lifted cache hit ratio 45%→90%, and
that without it the app "works but slower." **Git history contradicts
this:** commit `d5c9b95` — the commit that introduced Dragonfly — already
used it only for the in-flight marker. No version of the code ever stored
or served feed content from Dragonfly. Treat that document as a design
intent that was never built. What actually makes the feed fast:

1. **Supabase `feed_items`** — the real content cache; persistent, shared by
   every user and replica.
2. **Stale-serve + background refresh** (`fetchWithCache`) — users get rows
   immediately; refreshes happen fire-and-forget.
3. **Batched prefetch** (`buildFeedCachePrefetch`) — ~4 Supabase queries per
   feed request instead of ~120.
4. **In-process caches** — image proxy 40 MiB LRU (web builds only),
   service-level memory caches.

## 3. Behavior matrix

### With Dragonfly connected

| Scenario | Behavior |
|---|---|
| Live scrape starts | Marker SET (10s TTL) so other replicas can see it |
| Same artist requested on another replica within 10s | That replica polls the marker (100ms interval, ≤10s), then serves fresh Supabase rows |
| Scrape finishes | Marker DELeted; waiters proceed |
| Same replica, same artist | Handled by the in-process `_inFlightLocal` map — Dragonfly not even consulted |

### Without Dragonfly (current production state)

Every client method short-circuits on `!_connected` — `exists()` returns
false, `set()`/`delete()` return false, `get()` returns null. **Zero added
latency.** Coalescing falls back through two remaining layers:

1. **Same replica:** `_inFlightLocal` map — full coalescing, unaffected.
2. **Across replicas:** the Supabase lease
   (`tryClaimSystemCacheLease` / `feed_refresh_lock:*` keys) — only one
   replica wins the lease and scrapes. Losers serve cached rows if any
   exist.

**The one real gap:** if two replicas simultaneously miss on an artist with
*no cached rows at all* (never scraped, or force-refreshed), the lease loser
returns an **empty list** instead of waiting ≤10s for the winner's fresh
data. The user sees a blank slot until their next refresh. Rare, cosmetic,
and arguably better UX than a 10-second stall. At a single replica (the
at-rest state), this gap cannot occur at all.

### Failure semantics (both directions)

- `init(failOpen: true)` — connection failure logs a warning and the app
  proceeds; nothing crashes, nothing blocks.
- Any operation error marks the client disconnected; subsequent calls
  short-circuit instantly.
- **Since 2026-07-06 (this branch):** disconnection is no longer permanent —
  see next section.

## 4. The reconnect loop (added 2026-07-06)

Before this change the client connected **once** per process (triggered by
the `_cacheReady` sentinel on the first HTTP request) and a failure set
`_connected = false` forever — a replica that booted while Dragonfly was
down ignored it for its entire lifetime, so re-enablement required a
revision restart.

Now (`dragonfly_cache_service.dart`):

- While disconnected, the client PINGs Dragonfly every **3 minutes**
  (`_reconnectInterval`). Chained single timers — never more than one
  pending attempt, no overlap with the 5s connect timeout.
- Armed from `init()`'s fail-open path **and** from every operation's error
  path (`_markDisconnected()`), so a Dragonfly that drops mid-flight is also
  re-adopted when it returns.
- Retry attempts log at **FINE** (dropped at production's INFO level →
  zero Log Analytics ingestion while Dragonfly is absent). The state change
  logs at INFO: `[dragonfly_cache] Reconnected to <host>:<port> ✓`.
- `close()` cancels the timer (clean shutdowns/tests).
- Observability: `/monitor/cache` includes `reconnect_attempts` and
  `reconnect_pending`.

**Consequence:** with `DRAGONFLY_URL` set, the backend adopts a
newly-started Dragonfly within ~3 minutes, no restart. Activation becomes a
single infrastructure action.

## 5. Activation

### One-time prerequisite — ✅ DONE 2026-07-07

`DRAGONFLY_URL=redis://xene-dragonfly:6379` was permanently re-added to
`xene-backend` (revision `--0000022`) and verified in startup logs at 02:17
UTC: env picked up, fail-open with Dragonfly at 0 replicas, reconnect loop
idling at FINE. Nothing to do here — kept for the record:

```powershell
# Already applied. Only needed again if the env var is ever removed.
az containerapp update -g xene-rg -n xene-backend `
  --set-env-vars DRAGONFLY_URL=redis://xene-dragonfly:6379
```

Note: re-running this creates a new backend revision (restart). Remember the
scheduler arms on the **first request** after any restart — send a probe
request afterwards.

### Activate (the one command)

```powershell
az containerapp update -g xene-rg -n xene-dragonfly --min-replicas 1
```

All backend replicas adopt it within ~3 minutes automatically.

> **Pre-reconnect-loop fallback:** if the currently deployed backend image
> predates the reconnect loop, activation additionally requires restarting
> the backend so `init()` runs again:
> `az containerapp revision restart -g xene-rg -n xene-backend --revision <active-revision-name>`

### Verify activation

1. Backend logs (within ~3 min):
   `[dragonfly_cache] Reconnected to xene-dragonfly:6379 ✓` — or on a fresh
   boot: `[STARTUP] DragonflyDB cache initialized ✓`.
2. `/monitor/cache` (admin-only) shows `"connected": true` and SET/EXISTS
   counters increasing under feed load.
3. `az containerapp replica list -g xene-rg -n xene-dragonfly -o table`
   shows one replica.

### Deactivate

```powershell
az containerapp update -g xene-rg -n xene-dragonfly --min-replicas 0
```

Backends notice on their next operation (marker write fails → fail-open →
reconnect loop arms) and continue in fallback mode. `DRAGONFLY_URL` can
stay set.

### Right-sizing when activating

The original deployment (1 vCPU / 2 GiB) was ~10× oversized for marker
storage and cost **$22.54 per 16 days**. Start at **0.25 vCPU / 0.5 Gi**:

```powershell
az containerapp update -g xene-rg -n xene-dragonfly --cpu 0.25 --memory 0.5Gi --min-replicas 1
```

When re-enabling for real (multi-replica era), consider also moving the
per-process rate limiters (`lib/src/utils/rate_limiter.dart`) and optionally
the image-proxy byte cache into Dragonfly, so the ~$5–8/mo buys distributed
correctness rather than just markers.

## 6. When to activate — and when not to

**The trigger is topology, not user count.** Activate when:

- `az containerapp replica list -g xene-rg -n xene-backend -o table`
  **routinely shows ≥2 replicas at rest** (sustained concurrent load, not
  momentary bursts), and/or
- backend logs show spikes of
  `[feed_cache] Refresh lease BUSY ... returning empty` (the cold-miss gap
  actually biting).

At that point three per-process compromises compound — coalescing, rate
limiters loosening to ~2–3× effective limits, split image-cache hit rates —
and one shared store fixes all three.

**Do NOT activate merely because:**
- User count grew. Feed reads are I/O-bound (the replica mostly awaits
  Supabase); a single 0.25 vCPU Dart replica sustains high concurrency.
  2k registered users with a few hundred active may never hold 2 replicas.
- Old docs said the app is slow without Redis (see Myth vs. reality).

**The alert that watches this for you** (metric `Replicas` verified to exist
on the Container App; ~$0.10/mo):

```powershell
az monitor action-group create -g xene-rg -n xene-alerts --short-name xene `
  --action email owner k70391@gmail.com

$backendId = az containerapp show -g xene-rg -n xene-backend --query id -o tsv
az monitor metrics alert create -g xene-rg -n xene-backend-sustained-multireplica `
  --scopes $backendId `
  --condition "avg Replicas >= 2" `
  --window-size 1h --evaluation-frequency 15m `
  --severity 3 `
  --action xene-alerts `
  --description "Backend held >=2 replicas for 1h - consider re-enabling Dragonfly: az containerapp update -g xene-rg -n xene-dragonfly --min-replicas 1 (see docs/DRAGONFLY_CACHE_BEHAVIOR_AND_ACTIVATION.md)"
```

## 7. Hard warnings

- ⚠️ **Never add a KEDA scale-from-zero rule to `xene-dragonfly`.** The
  backend's 3-minute reconnect probe would wake it within minutes of every
  scale-down, making it effectively always-on — the $22.54/mo problem under
  a new name. Wake triggers must express *demand*; the probe only expresses
  *existence*.
  **2026-07-10 correction:** this happens *partially* even with no rule
  added — TCP ingress alone gives the probe a wake path. Cost is small
  (~$1–2/mo) because activations are brief, but see §9.
- ⚠️ **Full closed-loop automation** (alert → runbook that scales Dragonfly)
  was evaluated and deliberately deferred: it requires a managed identity
  with infra write access plus flap-prevention logic, for an event that is
  rare, gradual, and non-urgent (the Supabase lease keeps the app correct in
  the meantime). Revisit only if multi-replica operation becomes routine.
- ⚠️ **Use `redis://xene-dragonfly:6379`**, never the `https://...internal...`
  FQDN form (fails for raw TCP/RESP — proven in June 23 revision history).

## 8. Related documents

- `docs/Changelog_2026-07-06.md` — Session 1 (retirement + cost math),
  Session 2 (scheduler fix, detailed Dragonfly notes, reconnect loop,
  alert setup).
- `docs/education/dragonfly_reconnect_loop.educational.md` — line-by-line
  walkthrough of the reconnect implementation and its design decisions.
- `docs/education/feed_cache_distributed.educational.md` — the coalescing
  design in `feed_cache.dart`.
- `docs/performance/REDIS_DRAGONFLYDB_IMPLEMENTATION.md` — **historical**;
  performance claims superseded by this document (see Myth vs. reality).

---

## 9. 2026-07-10 finding: the reconnect probe wakes the scaled-to-zero app

**Discovered during a Jul 3–9 cost review.** This section corrects the
claim (TL;DR + §7) that a scaled-to-zero Dragonfly with `scaleRules: null`
can only come back via manual action. It cannot *serve* the app without
manual action, but it **does briefly activate on its own** — and bills for
it.

### Evidence (all verified against live Azure, 2026-07-10)

1. **Billing** — Cost Management shows `xene-dragonfly` accruing
   "Standard vCPU/Memory **Active** Usage" every day after retirement:
   $0.065 (Jul 7), $0.048 (Jul 8), $0.036 (Jul 9), $0.016 (Jul 10,
   partial-day data — billing lags, so the apparent decline is not
   meaningful).
2. **Replica metric** — `az monitor metrics list --metric Replicas`
   (hourly max, Jul 7–10) shows the replica count hitting **1** in
   scattered hourly buckets every day: 4 buckets on Jul 7, 3 on Jul 8,
   2 on Jul 9, and 8 consecutive buckets on Jul 10 (14:00–21:00 UTC).
   `az containerapp replica list` between activations shows `[]`.
3. **Config** — `minReplicas: 0`, `maxReplicas: 1`, `scaleRules: null`,
   internal **TCP** ingress on 6379 (unchanged since retirement).
4. **The client** — `DRAGONFLY_URL=redis://xene-dragonfly:6379` is set on
   `xene-backend` (by design, §5 prerequisite), so the §4 reconnect loop
   PINGs `xene-dragonfly:6379` every 3 minutes, each PING being a real
   `Socket.connect` to the TCP ingress.

### Mechanism (deduced — consistent with all evidence, not independently confirmed in Azure docs for the `scaleRules: null` case)

Container Apps treats an inbound connection to a scale-to-zero TCP-ingress
app as an activation signal even without an explicit KEDA rule. Each
3-minute probe (or occasional marker write while transiently `_connected`)
can wake the replica; it runs for the scale-in cooldown window, then
returns to zero; repeat. Activations are brief and sporadic rather than
continuous — hence ~$0.02–0.07/day (~$1–2/mo) instead of the $2.59/day
always-on cost. The §7 warning ("a scale rule would make the probe keep it
always-on") described a difference of degree, not kind: TCP ingress alone
already gives the probe a partial wake path.

**Watch item:** Jul 10 showed 8 *consecutive* active hours — if that
becomes the norm, the cost trends toward always-on and the mitigation
below stops being optional.

### Why this was missed

The 2026-07-06/07 design assumed "0 replicas + no scale rule = inert," and
`_sendCommand`'s FINE-level logging (deliberate, to avoid Log Analytics
cost) means the probes leave no INFO-level trace. Nothing was wrong in the
code or the manual steps — the gap was an undocumented Azure activation
behavior on TCP ingress.

### Mitigation options — decision 2026-07-10: **observe** (option 4)

Owner chose to leave everything as-is and watch the actual cost before
acting. Revisit if the daily charge grows past ~$0.10/day or activations
become continuous (see watch item above).

| Option | Effect | Trade-off |
|---|---|---|
| **Delete the `xene-dragonfly` container app** | Wake target gone; $0. Probe fails on DNS instantly. | Reactivation (§5) becomes "redeploy the app" instead of one command. |
| **Remove `DRAGONFLY_URL` from `xene-backend`** | Probe pings `localhost:6379` — fails in-container, never reaches Dragonfly. | Undoes the §5 "permanent" prerequisite; reactivation needs the env var re-added (new revision + scheduler probe request, see §5 note). |
| **`az containerapp stop -g xene-rg -n xene-dragonfly`** (stop, don't delete) | Stopped apps don't activate on traffic; config preserved. | Reactivation becomes `az containerapp start` + the §5 min-replicas command. |
| **Accept the ~$1–2/mo** | Nothing changes; §5 one-command activation stays true. | Pays a small tax; Jul 10's 8-hour stretch suggests it may grow. |

Whichever is chosen, update the **Status** line at the top of this
document and §5 accordingly.
