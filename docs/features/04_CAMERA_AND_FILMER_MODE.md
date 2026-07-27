# 📹 04. Camera Architecture: Gameplay Chasing vs. Filmer / Replay Edit Suite
**Status:** 💡 `EXPLORATION` | **Priority:** `MEDIUM` | **Key File:** [res://scripts/player/ChaseCamera.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/player/ChaseCamera.gd)

---

## 🧐 Conceptual Breakdown: Gameplay Camera vs. Filmer / Edit Mode
A common point of ambiguity in skate simulator design is distinguishing between **Real-Time Gameplay Chase Camera adjustments** and a **Dedicated Filmer / Replay Edit Mode**. Here is the architectural separation and why both serve crucial, distinct purposes:

### 1. Real-Time Gameplay Camera (Tactile Immersion & Control Clarity)
- **Primary Goal:** Provide unambiguous, dependable situational awareness for precise trick timing while translating physical momentum into sensory feedback.
- **Why Dynamic FOV matters for *Gameplay*:**
  - In real life, speed alters physical perception. In a game screen, rolling at $2.0\text{ m/s}$ versus $7.0\text{ m/s}$ with a static field of view ($75^\circ$) can feel visually slow or flat.
  - By subtly expanding camera FOV up to $\sim 85^\circ \to 88^\circ$ as speed climbs, peripheral ground textures streak past faster—instantly conveying velocity and making fast carves feel intense!
  - **Crucial Rule:** Gameplay camera tuning must NEVER sacrifice gameplay precision. It must remain smoothly anchored behind travel direction (`_camera_side_smooth`), maintain centered subject vanishing points (`h_offset = 0.0`), and avoid excessive swinging or shaky-cam lag that could disorient player manual catching!

### 2. Dedicated Filmer / Replay & Edit Suite (Post-Run Content Creation)
- **Primary Goal:** Simulate an authentic skate videographer ("filmer") trailing alongside the rider with classic equipment (e.g., VX1000 fisheye lens, low-angle rolling skate handles, or HD drones) to capture cinematic video clips of completed lines and gap stunts.
- **Key Mechanics for an Edit / Filmer Mode:**
  - **Time & Line Recording:** Buffer recent physics states (skater position, board rotation, foot transforms, wheel particles) over a rolling window (e.g., last 30 to 60 seconds of gameplay).
  - **Free / Keyframed Filmer Controls:** Upon entering "Replay / Edit Mode", gameplay pauses and transitions to an timeline scrubbing UI.
  - **Customizable Lens & Angles:**
    - Toggle extreme VX1000 Fisheye distortion shaders with circular vignette framing.
    - Freely reposition camera targets (e.g., low-angle ground roll near front wheels, overhead crane follow, or static tripod perched on a concrete plaza ledge).
    - Add custom keyframes for slow-motion velocity curves (`Engine.time_scale` adjustments) during mid-air Tre Flips over stairs!

---

## 🛠️ Discussion Topics & Next Steps
1. **Immediate Gameplay Enhancement:** Should we integrate a gentle, optional speed-scaled FOV modifier straight into `ChaseCamera.gd` right now to heighten normal cruising speed sensation, while keeping hardcore replay editing reserved for a dedicated future module?
2. **Replay Buffer Efficiency:** When preparing for Replay / Filmer Mode later, should we structure our frame recording as lightweight state snapshots (`TrickSignature`, `Transform3D`, foot poses) to allow smooth scrubbing without bloating system memory?
