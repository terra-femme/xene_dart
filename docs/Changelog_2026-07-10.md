# Changelog � 2026-07-10

## [Session Title]

### Error / Issue
<!-- Describe the problem encountered -->

### Root Cause
<!-- Why did this happen? -->

### Fix


### Education
<!-- What concept does this illustrate? -->

### Best Practices
<!-- What should be done going forward? -->

### Notes
<!-- Any other observations -->

---

## Dancing Points noise-ball rebuild, sidebar portrait fix, branch cleanup

### Error / Issue
1. **Center "noise-ball" invisible / wrong.** User couldn't see the line-noise in the brain's central void, then reported it "always looks like disconnected lines floating in space" instead of a connected ball of scribbles like their Framer reference.
2. **Sidebar moving in portrait.** User saw motion in the sidebar in portrait mode and asked if I'd changed the autoscroll (I had not).
3. **Branch sprawl.** Many stale local/remote branches needed cleanup.

### Root Cause
1. `buildWireframeBlob`/`updateWireframeBlob` existed in `scene.js` but were **never called** — nothing rendered the ball (color was a red herring). Once wired in, the deeper issue surfaced: it was built as `SphereGeometry → EdgesGeometry → LineSegments`, and `EdgesGeometry` emits **independent edge segments**, so it can never look like continuous strokes. A scribble is a *pen path* (connected polyline through a noise field), a fundamentally different construction — the classic LLM miss on this shape.
2. The vertical sidebar auto-crawl was correctly gated to landscape (`needsScroll = isLandscape && …`). The moving element was the **articles carousel** (`_ArticlesSlider._timer`, a 5s `Timer.periodic`) which was gated only by reduce-motion and article count — **not orientation** — violating the file's own invariant ("portrait should remain still").
3. "Commits ahead of main" was misleading because most branches were **squash-merged** (unique commits remain even though content is merged); had to verify via `git diff origin/main...branch` and `gh pr list`.

### Fix
- **Noise-ball** (`scene.js`): wired `buildWireframeBlob` into `createScene`; rewrote it as continuous `THREE.Line` strokes that walk a trig noise field and tangle into a ball (soft containment to `radius`); luminous white `0xeaf4ff`; drums drive per-vertex dance + scale punch. Tuned to fit the void: `radius 0.5, strokeCount 30, step 0.04`. Cache-buster bumped to `?v=noiseball-3`.
- **Sidebar** (`xene_sidebar.dart`): `_startTimer()` now bails in portrait (`if (!widget.isLandscape) return;`) and added `didUpdateWidget` so a live rotation cancels/restarts the timer. Manual swipe still works. `dart format` + `dart analyze` clean.
- **Branches**: committed visualizer + sidebar work in 2 commits, pushed `feat/dancing-points-stems`, opened/merged PR #66 (squash, green CI). Deleted 4 merged local + 3 merged/abandoned remote branches. Kept 3 unmerged branches per user (`claude-backend-debug-…`, `feat/safari-discoveries`, `wip/swipe-nav`).

### Education
`EdgesGeometry`/`LineSegments` draws disconnected edge pairs; `THREE.Line` draws a connected polyline. Organic "scribble" visuals need the latter following a flow/noise field, not a wireframed primitive. Also: a git branch showing "N commits ahead" of main is **not** proof it's unmerged — squash-merges leave orphan commits; verify with the content diff (`git diff main...branch`) and PR state, not the commit count.

### Best Practices
- Verify a function is actually *called/rendered* before debugging its output (the ball was dead code — nearly a black-hole debug session avoided by checking wiring first).
- Before deleting branches, cross-check `git diff` content **and** `gh pr list --state all` merge status; only force-delete after confirming the PR merged.
- Feature-branch → PR → green CI → squash-merge; never merge/push main directly. No commit/PR attribution footers.

### Notes
- **Visualizer is merged to `main` (af7cf9f) but NOT visually verified on device** — user merged on green CI. Needs a look: does the ball sit in the void and react to drums? If not, check Reactive Source→Drums / React meter to confirm the drums stem loaded.
- Pending: Phase 2 (brain vocal-dots) and Phase 3 deeper tuning (live drum-driven noise re-warp, currently only scale). Plan: `~/.claude/plans/parallel-zooming-volcano.md`.
- Dependabot PRs #57–61 left open/untouched.

---

## Azure cost review (Jul 3–9) — retired Dragonfly is waking itself up

### Error / Issue
Azure portal showed **over $9 for the last 7 days** despite the 2026-07-06
cost fixes and a ~$10–15/mo target. Additionally, `xene-dragonfly` —
retired and scaled to 0 replicas — was still accruing small daily
"Active Usage" charges ($0.02–0.07/day), which the user had been told was
impossible without a manual scale-up.

### Root Cause
1. **The $9 was trailing history, not current spend.** Cost Management
   (verified via `az rest` against the Query API) showed $7.51 of the
   Jul 4–10 window's $9.05 was spent Jul 4–6, before the fixes landed.
   Post-fix run rate is ~$0.40–0.48/day (≈$12/mo) — on target.
2. **Dragonfly wakes itself.** The backend's 3-minute reconnect probe
   (`dragonfly_cache_service.dart`, `_reconnectInterval`, added 2026-07-06)
   opens a real TCP connection to `xene-dragonfly:6379` because
   `DRAGONFLY_URL` is deliberately set on `xene-backend` (revision
   `--0000022`). Azure Container Apps treats an inbound connection to a
   scaled-to-zero **TCP-ingress** app as an activation signal even with
   `scaleRules: null` — so the "is Dragonfly back yet?" probe resurrects
   the thing it probes. Verified via the `Replicas` metric: the app hit
   1 replica in scattered hours every day since retirement (8 consecutive
   hours on Jul 10).

### Fix
No code change (user chose to **observe** the ~$1–2/mo cost). Documented:
- `docs/DRAGONFLY_CACHE_BEHAVIOR_AND_ACTIVATION.md` — new §9 (evidence,
  mechanism, mitigation table: delete app / remove env var /
  `az containerapp stop` / accept), plus corrections to the TL;DR row and
  §7 warning that claimed manual scale-up was the only wake path.
  Committed locally on `main` as `e7e556a` (file was previously untracked —
  `docs/` is gitignored; force-added per existing precedent). Not pushed.

### Education
"Scaled to zero" ≠ inert when an app has TCP ingress: activation triggers
express *reachability*, not *demand*. A liveness/reconnect probe pointed at
a scale-to-zero service is a self-defeating pattern — the probe itself is
traffic. Also: a "last 7 days" cost total mixes pre- and post-fix days;
always look at the **daily** granularity before judging whether a fix
worked.

### Best Practices
- Query costs with daily granularity + per-resource/meter grouping
  (`Microsoft.CostManagement/query` via `az rest`) instead of trusting the
  portal's single rolled-up number.
- When a "impossible" charge appears, check the `Replicas` metric — it
  shows activations that leave no log trace (the probe logs at FINE only).
- Revisit trigger recorded in doc §9: act if Dragonfly exceeds ~$0.10/day
  or activations become continuous.

### Notes
- Post-fix steady state: backend ~$0.20/day, ACR Basic $0.167/day (now the
  largest fixed cost, ~$5/mo flat), Dragonfly wake tax $0.02–0.07/day.
- Memory updated: `project_azure_cost_posture.md` (run rate confirmed,
  wake behavior, observe decision; also corrects the stale "DRAGONFLY_URL
  removed" note — it was re-added 2026-07-07 by design).
- Jul 10 showed 8 consecutive active hours vs 2–4 scattered on prior days —
  the watch item to keep an eye on.
