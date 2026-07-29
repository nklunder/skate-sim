# 🌊 07. Feel Tuning — the "flow" problem
**Status:** 🚧 `PLANNED` | **Priority:** `HIGH` | **Parent document — start here**

> **This is the entry point for the feel work.** Each numbered task below has its own document with
> the measurements, the model, and the interactions. Read this file for the goal and the ordering;
> read the child for how to actually do one.

---

## 🎯 The problem, stated honestly

The sim is in good physical shape and does not *feel* finished. Riding it reads as correct but
**mechanical** — it is missing the flowing, weighted quality of Session. Two separate observations
from play:

1. **Carving does not flow.** Especially at low speed, the board pivots rather than arcs.
2. **Tricks look mechanical.** The deck's rotation reads as machine-driven rather than thrown.

Both turned out to have specific, measurable causes rather than being vague polish. A third
contributor is presentation, which is real but must not be used to paper over the first two.

## 🔍 What is already good — do not re-litigate

A fresh session should not spend time rediscovering these. They are settled and working:

- `velocity` is an **authoritative world vector**, not derived from facing. Slopes, crooked landings
  and momentum-based bails are all expressible because of it.
- **Wheel anisotropy** — free along the rolling axis, gripping across it — is one mechanism that
  produces imperfect-landing drift, the speed cost of carving, and sideways scrub.
- The **rider is a real body** (`RiderBody`): legs with a tuck and contact clamp, and torsion between
  feet and shoulders. Airborne foot motion is driven by the legs, not authored curves.
- **Rotation is rate-based** with targets derived from a turn count, so held rotation composes.
- Every threshold is **exported**; orientation conversions live in one `RIG FRAMES` block; five
  regression suites exist and new assertions are **falsified** before being trusted.

## 🧭 The three tasks, in order

| # | Task | Document | Why this position |
|---|---|---|---|
| **07a** ✅ | Carve curvature (`ω = v/R`) | [07a_CARVE_CURVATURE.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07a_CARVE_CURVATURE.md) | **Diagnostic as much as a fix.** Cheapest way to learn whether "flowy" is a physics gap or a presentation gap — **implemented, awaiting the play verdict** |
| **07b** | Rotation dynamics (spin-up, spin-down, wobble) | [07b_ROTATION_DYNAMICS.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07b_ROTATION_DYNAMICS.md) | Biggest single win on "mechanical", and it is real physics rather than polish |
| **07c** | Presentation (sound, optical flow, FOV) | [07c_PRESENTATION_FEEL.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07c_PRESENTATION_FEEL.md) | Probably a **large** part of the answer — but it would MASK 07a and 07b rather than fix them |

**The ordering is the important part.** 07a first because it answers a question: if carving at
$2\text{ m/s}$ suddenly feels right, the diagnosis is confirmed and 07b/07c are worth doing properly.
If it still feels flat afterwards, the answer is mostly presentation, and that is worth knowing
*before* spending more time tuning physics in pursuit of it.

## ⚠️ These are deliberate re-baselines, not no-ops

Most work in this project has been verified as byte-identical. **07a and 07b are not.** Both change
figures the suites assert:

- **07a** moves every turn amount in `carve_and_push`. ✅ Done — the moved figures are tabulated in
  [07a](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07a_CARVE_CURVATURE.md), along with the two thresholds re-baselined and the reasoning for each. The other
  three suites came out byte-identical, and `ground_physics` moved exactly one line.
- **07b** shifts when tricks complete, moving timings in `curb_flip_repro`.

That is expected and correct. The discipline still applies: run all five suites, **diff the printed
numbers**, and state which moved and why. What must not happen is a figure moving silently, or a
threshold being nudged to make a case pass.

## 📌 Also outstanding (not part of this feature)

So a returning session has the full picture:

- **Deck rotation plan** — Stage D (naming: a double kickflip still reports as "Kickflip", since
  `TrickSignature.flip` is a direction and not a count) and Stage E (the `flip_scoop_sync` toggle).
- **Grind & slide system** ([02](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/02_GRIND_SYSTEM.md)) — where the torsion between rider and board stops being dormant, and where the
  frontside/backside asymmetry of `twist_external_deg` / `twist_internal_deg` finally gets tested.
- **[CLEANUP.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/CLEANUP.md)** — #4 (foot rotation angle wrap) and #8 (torsion coverage) both become live at the
  grind work; #2 and #3 are open feel decisions.
