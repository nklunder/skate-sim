# 🧹 CLEANUP.md — Known Debt, Deferred Work & Latent Traps

Things a working session **noticed but deliberately did not do**, recorded so they are not rediscovered from scratch later. Every entry states what it is, *why it was left*, and what "done" looks like.

> **Instruction for AI agents:** Read this before proposing a refactor — an item here may already have a decided approach, or may be deliberately open pending a design call from the user. When you complete one, delete its entry and log it in [CHANGELOG_LEDGER.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/CHANGELOG_LEDGER.md). **Do not treat this list as a work queue to burn down** — several items are here precisely because doing them without a reason would be churn.

**Legend:** 🔨 ready to do · ❓ blocked on a design decision · 🕳️ latent trap, no action yet · 🧊 intentionally frozen

---

## 🔨 1. `_evaluate_touchdown_landing()` does five things in 106 lines

`res://scripts/player/SkaterController.gd`

The longest function in the project. In order, it: settles the feet, judges the deck catch against `catch_cone_deg`, transfers residual yaw from `BoardPivot` to the rig, tests for a sideways wash-out, and classifies the landing (manual / bail / clean).

**Why left:** the seams are clean and the extraction is mechanical, but it is a judgment call rather than an obvious win, and it was proposed at the end of a session that had already produced two mishaps. Not worth stacking more churn onto tired verification.

**Done looks like:** `_judge_deck_catch() -> bool` and `_classify_landing()` extracted, with the fall-through between the catch check and the manual check preserved. **That fall-through is load-bearing** — an early `return` there is what once made an incomplete flip present as "manuals don't work after a flip trick" rather than as a failed landing (BUG_ARCHIVE #1). Verify with all three suites reproducing every figure exactly.

---

## ❓ 2. Push impulse fires on every press while the animation is gated

`_apply_push_inputs()` in `SkaterController.gd`, `FootRig.start_push()`

`FootRig.start_push()` refuses while either foot is off its rest pose, so a press arriving mid-stroke is dropped. The **physical impulse is applied regardless**. Mashing the push button therefore accelerates at full rate while the shoe visibly kicks only once.

**Why left:** the obvious fix — gate the impulse on the animation — is exactly the animation-decides-a-gameplay-outcome coupling this codebase has removed everywhere else (see AGENTS.md critical rule 9). The correct shape is a **physics-side** cooldown that the animation happens to match, not an animation vetoing physics. `_since_push` already exists as the timer; the change is roughly one line.

**Blocked on:** whether pushing *should* be rate-limited at all, and at what cadence. That is a feel decision, not an engineering one. **Ask before implementing.**

---

## 🕳️ 3. The controller reads input polled one frame earlier

Godot runs `_physics_process` in **tree order, parents before children**. `SkaterController` is on `SkaterRoot`; `RiderInput` and `TrickState` are its descendants:

```
SkaterRoot        (SkaterController)   ← ticks FIRST
└── RiderInput                          ← polls the device SECOND
    └── TrickState                      ← recognises gestures THIRD
```

So every frame the controller acts on stick values sampled on the **previous** frame — about 16.7 ms of input latency at 60 Hz.

**Why left:** it is pre-existing behaviour that predates the input split, all current tuning was done against it, and both regression suites bake it in. Removing it would change every printed figure, so it cannot be verified as a no-op refactor — it is a deliberate feel change that needs playing.

**If it is ever addressed:** the fix is to drive `RiderInput.tick()` / `TrickState.tick()` explicitly from the top of `SkaterController._physics_process()`, the same pattern `ChaseCamera.follow()` and `FootRig.solve()` already use, rather than reordering nodes. Expect every suite number to move; re-baseline deliberately.

*(Related and much smaller: `FootRig.solve()` runs before `camera_pivot.follow()`, so the ankle pegs resolve against last frame's camera yaw. This is **preserved on purpose** — it is what the pegs always did, and changing it would alter their feel for no stated reason.)*

---

## 🕳️ 4. The foot rotation spring does not wrap angles

`FootRig.Channel.integrate()`:

```gdscript
_vel_rotation += ((target_rotation - node.rotation) * stiffness - _vel_rotation * damping) * delta
```

A plain componentwise `Vector3` subtraction with no `angle_difference()`. Harmless today — every rotation target is currently the rest pose — and fine for the small angles `01_FOOT_ANIMATIONS.md` calls for (ankle toe-up ≈ 15°, crouch +5° to +10°).

**The trap:** any foot rotation target approaching ±180° would spin the long way round, or oscillate. Most likely to bite on a future grind or a full-body trick where a shoe is authored near a half-turn.

**Done looks like:** wrapping each component through `angle_difference()` before applying stiffness — but only when a target genuinely needs the range. Doing it pre-emptively costs three trig calls per foot per frame for no current benefit.

---

## 🕳️ 8. `RiderBody.twist_deg` has no regression coverage yet

`res://scripts/player/RiderBody.gd`

The torsion is in and verified by probe — rigid is a provable no-op, softening produces real lag, and the anatomical clamp mirrors for goofy — but nothing in the suites exercises it, because at the default `twist_follow` it is dormant.

**Why left:** the same reasoning CLEANUP #5 used for `FootRig`, which worked well: write the suite *alongside the first real use*, not before. Until a ledge can constrain the board there is nothing to assert beyond restating the mechanism back to itself.

**Done looks like:** written at the start of the grind/slide work, asserting the invariant that caught the one real bug here — **tracked `twist_deg` must always equal the board's actual yaw offset from the rider** — plus the frontside/backside asymmetry across `{regular, goofy}`.

---

## 🧊 6. Deliberately dead code — do not "clean up"

| Symbol | Status |
|---|---|
| `SurfaceProbe.find_edge_near()` | Uncalled. Spline-free ledge discovery, written as Stage 1 groundwork for the grind system ([02_GRIND_SYSTEM.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/02_GRIND_SYSTEM.md)). **Keep.** |
| `SurfaceProbe._exclude` | Always empty — the rig is a plain `Node3D` with no physics body, so there is nothing of its own to hit. Kept for when that changes. |
| `TrickSignature.lands_switch` / `body_with_scoop` | Unused by any `TrickNames.TABLE` row today, but part of the naming API — they exist so rows *can* match on them. **Keep.** |
| `SkateBoardConfig` — 8 of 9 fields | Only `turn_speed` is read. Already flagged honestly in the file's own header. Either wire them up or delete them when hardware customisation ([06](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/06_MODULAR_HARDWARE_CUSTOMIZATION.md)) is designed — **not before**, since that feature will decide their shape. |

---

## 🕳️ 7. The catch cone is measured once, at `_ready()`

`_measure_catch_cone()` derives `catch_cone_deg` from `SkateDeckMesh.deck_extents()` — deck half-width and underside height — a single time on startup.

That is correct today because the deck never changes. **Modular hardware customisation ([06](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/06_MODULAR_HARDWARE_CUSTOMIZATION.md)) breaks it**: swapping to a wider deck lowers the roll angle at which a rail strikes the ground, and the cone must move with it or landings will be judged against the previous board's geometry.

**Done looks like:** `_measure_catch_cone()` re-invoked whenever the deck model changes. The function is already idempotent and reads everything it needs from the mesh, so this is a call site, not a rewrite.

---

## 📋 Recently cleared

Kept briefly so a returning agent can see these are **already done** and does not re-propose them:

- Seven ad-hoc orientation sign derivations → one conversion layer (`94f5974`)
- `FootInputState` split into `RiderInput` / `TrickState` (`9412985`)
- Two-stage balance law given one home on `TrickState` (`2a5b4a7`)
- `max_push_speed` clamping the along-axis component instead of total speed (`e04cb31`)
- Stale `pop_impulse_scale` on the keyboard pop path (`e04cb31`)
- Dead: `_since_touchdown`, `SurfaceProbe.set_space()`, `last_pop_type`, `active_flip` as a field (`e04cb31`)
- ~15 magic thresholds exported across `TrickState` and `SkaterController`
- `FootRig` test coverage — written alongside the first physics-driven foot motion, as the entry said it should be (`tests/foot_rig.tscn`, 12 cases across `{regular, goofy} × {forward, switch}`)

---

## ❓ 9. Grounded turning has no speed term

`_apply_steering()` in `SkaterController.gd`

`turn_rate = lean * turn_speed * _lean_authority()` produces a flat $\approx 169^\circ/\text{s}$ at full lean whether the skater is doing $7\text{ m/s}$ or $1\text{ m/s}$. Physically lean sets a turn RADIUS, so $\omega = v/R$ — roughly right when fast, and about $4\times$ too fast at walking pace, where the board pivots instead of arcing.

**Why left:** it is a deliberate feel change that re-baselines every carve figure, not a bug fix. Fully specified in [07a_CARVE_CURVATURE.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07a_CARVE_CURVATURE.md), including the kickturn interaction.

---

## ❓ 10. The deck's rotation starts and stops in a single frame

`_impart_deck_rotation()` and the Layer 3 block in `SkaterController.gd`

Angular velocity goes $0 \to 13.6^\circ/\text{frame}$ on the first airborne frame, and full rate $\to 0$ on the frame it completes. Infinite angular acceleration at both ends, and the main reason tricks read as mechanical. The constant rate *between* them is correct and should stay.

**Why left:** same as #9 — a deliberate change that moves trick timings. Specified in [07b_ROTATION_DYNAMICS.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07b_ROTATION_DYNAMICS.md), along with the precession wobble and the interactions with the leg tuck and the free-spin handover.
