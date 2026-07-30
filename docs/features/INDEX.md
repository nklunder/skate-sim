# 🎯 Skate Sim V2 — Feature Roadmap & Architectural Specifications

This directory serves as the centralized technical engineering reference for planned, in-progress, and completed subsystems in **Skate Sim V2**. 

> **Instruction for AI Agents:** When implementing or refining a specific gameplay feature, open and review the corresponding specification document here BEFORE editing code. When a milestone completes, update its status tag to `✅ COMPLETED & DEPLOYED`, add a summary entry to [docs/CHANGELOG_LEDGER.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/CHANGELOG_LEDGER.md), and log any overarching structural invariants into [AGENTS.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/AGENTS.md). **Do not delete feature documents upon completion; retain them as permanent architectural manuals.**

---

## 🔥 High Priority Milestones (Active Exploration & Dev Focus)

| # | Feature Domain | File Reference | Status | Core Objective |
|---|---|---|---|---|
| **01** | **Procedural Foot Animations** | [01_FOOT_ANIMATIONS.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/01_FOOT_ANIMATIONS.md) | 🚧 `PLANNED` | Procedural shoe flick arcs, Shove-it tail sweeps, pop loading weight shift, and IK endpoint preparation. |
| **02** | **Grind & Slide System** | [02_GRIND_SYSTEM.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/02_GRIND_SYSTEM.md) | 🚧 `PLANNED` | Stage 2 of surface collision: spline-free edge discovery, truck/deck ledge lock-ins, and grind physics. |
| **07** | **Feel Tuning — "flow"** | [07_FEEL_TUNING.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07_FEEL_TUNING.md) | 🚧 `PLANNED` | **Parent doc — start here.** The sim is physically correct but reads as mechanical; three measured causes and the order to address them. |
| 07a | ↳ Carve Curvature | [07a_CARVE_CURVATURE.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07a_CARVE_CURVATURE.md) | 🚧 `PLANNED` | Turning has no speed term — $\omega = v/R$. Diagnostic as much as a fix; **do this one first**. |
| 07b | ↳ Rotation Dynamics | [07b_ROTATION_DYNAMICS.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07b_ROTATION_DYNAMICS.md) | 🚧 `PLANNED` | The deck starts and stops spinning in one frame. Spin-up, spin-down, and precession wobble. |
| 07c | ↳ Presentation Feel | [07c_PRESENTATION_FEEL.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07c_PRESENTATION_FEEL.md) | 🚧 `PLANNED` | Wheel rumble, optical flow, speed FOV. Probably a large part of the answer — deliberately ordered last so it cannot mask 07a. |
| 07d | ↳ Control Continuity | [07d_CONTROL_CONTINUITY.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07d_CONTROL_CONTINUITY.md) | ✅ `IMPLEMENTED` (1–2) | Physics audit. A power curve in the device layer was rescaling the carve model's only input; angular momentum was discarded at every takeoff. Items 3–6 filed, not done. |
| **03** | **Sound Design Engine** | [03_SOUND_DESIGN.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/03_SOUND_DESIGN.md) | 🚧 `PLANNED` | Procedural audio: speed-scaled polyurethane wheel rumble, maple tail cracks, and griptape catch thuds. |

---

## 🛠️ Medium & Future Priorities (Architecture & Concept Exploration)

| # | Feature Domain | File Reference | Status | Core Objective |
|---|---|---|---|---|
| **04** | **Camera & Filmer Mode** | [04_CAMERA_AND_FILMER_MODE.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/04_CAMERA_AND_FILMER_MODE.md) | 💡 `EXPLORATION` | Distinguishing real-time gameplay chase feel (dynamic speed FOV) vs. dedicated post-run replay/edit filmer suites. |
| **05** | **Full Character Rig** | [05_FULL_CHARACTER_RIG.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/05_FULL_CHARACTER_RIG.md) | 💡 `PLANNED` | Anatomical humanoid biped skeleton utilizing existing shoe coordinates as direct leg IK end-effectors. |
| **06** | **Modular Hardware Customization** | [06_MODULAR_HARDWARE_CUSTOMIZATION.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/06_MODULAR_HARDWARE_CUSTOMIZATION.md) | 💡 `PLANNED` | Decoupling skateboard assemblies into swappable slots (Decks, Trucks, Wheels, Grip, and Shoes/Apparel). |

---

## 📜 Feature Document Lifecycle
1. **`PLANNED / EXPLORATION`:** Requirements gathering, algorithmic theory, and design trade-offs are sketched in deep detail.
2. **`IN PROGRESS`:** Active coding phase where scripts and scenes are built against the document’s specification.
3. **`COMPLETED & DEPLOYED`:** Verified via headless testing; kept permanently in this directory as an authoritative maintenance manual.
