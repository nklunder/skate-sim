# 🐞 BUG_ARCHIVE.md - Resolved Skate Physics & Architecture Bugs

This document serves as an archival repository of past bug investigations, post-mortems, and resolved regressions in **Skate Sim V2**. AI agents and contributors should consult this document when investigating new regressions, unexpected behavior in rotation physics, or Switch/Fakie sign inconsistencies.

---

## ✅ Resolved Bugs & Post-Mortems

### 1. Flip Tricks Unlandable on Any Raised Surface
- **Symptom:** Reported as "kickflip into a manual on the curb stalls every time"; the manual was incidental, a plain kickflip onto the curb bailed identically.
- **Root Cause:** `is_flip_in_progress` cleared only after the deck swept a full $360^\circ$ at `flip_speed_deg`, a **fixed 0.60 s wall-clock duration** regardless of hang time — while hang time *shrinks with the height gained from takeoff surface to landing surface*. Popping onto the `y = 0.30` curb gave 35 frames against 36 needed: one frame short, deterministically. `_evaluate_touchdown_landing()` hit the primo branch and `return`ed **before** the manual-zone check, which is why it presented as "flip tricks break manuals".
- **Resolution:** Landing is now judged on the deck's orientation against `catch_cone_deg = min(atan(grip_friction), rail-strike angle)` — the friction cone a shoe can stamp an off-axis deck flat within, clamped by the roll angle at which the deck's rail would reach the ground before its wheels. Nothing in the landing path reads airtime, ledge height, gravity, or frame rate any longer.

### 2. 360-Spin Tricks Finished Yaw Before Roll
- **Symptom:** A tre flip's yaw ran at `spin_speed_deg * 2` (0.42 s) while its roll ran at `flip_speed_deg` (0.59 s), so the deck visibly stopped spinning at roughly $253^\circ$ of flip and kept rolling alone before halting.
- **Root Cause:** Independent fixed-rate animations with no shared notion of the trick as one physical event.
- **Resolution:** Fixed by `_impart_deck_rotation()`. Rotation is now imparted once at pop as a constant angular velocity, with both axes scaled onto one shared trick duration so roll and yaw always retire on the same frame.

### 3. "Slide" Stayed High on HUD Long After Landing
- **Symptom:** Read as wheel grip failing to scrub off drift after landing.
- **Root Cause:** **Not a physics bug at all** — the readout was mislabelled. `last_landing_slide` is a *latched* sample taken once inside `_evaluate_touchdown_landing()` and held until the next touchdown; nothing clears it, deliberately, because its whole job is to let `max_landing_slide` be tuned against a landing after the fact. Labelled bare `Slide` next to the live `Speed` it read as live state, so a persisting landing figure looked exactly like lateral velocity that never decayed. Instrumented headlessly on a $20^\circ$ landing at 5 m/s: live lateral speed fell `1.68 → 0.10 m/s` in 20 frames and to exactly zero by frame 30 (**0.5 s**) while the latched value sat at `1.682` for the full 3 s probe.
- **Resolution:** Fixed in the HUD only: split into `Slip` (live, from read-only `lateral_speed`) and `Last slide` (latched). The grip integrator was correct and left untouched.

### 4. Switch/Fakie Sign & Mirror Errors (Recurring Bug Class)
- **Warning:** Switch/Fakie sign errors are this project's recurring bug class — do not assume "validated" means immune.
- **History:** Three separate ones surfaced in a single session (reversed ankle pegs, inverted shuv naming, inverted body-rotation naming), each found by *play*, not by tests, because each fails silently as a mirror image rather than a hard crash or runtime error.
- **Rule of Thumb:** When touching anything rotational, always check it in all four of `{regular, goofy} × {forward, switch/fakie}` before calling a fix complete.
