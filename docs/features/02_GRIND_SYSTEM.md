# 🛹 02. Grind & Slide System (Stage 2 Surface Collision)
**Status:** 🚧 `PLANNED` | **Priority:** `HIGHEST` | **Key Files:** [res://scripts/physics/SurfaceProbe.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/physics/SurfaceProbe.gd), [res://scripts/player/SkaterController.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/player/SkaterController.gd)

---

## 🎯 Executive Summary & Architectural Heritage
In Stage 1 of Surface Collision, we engineered [SurfaceProbe.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/physics/SurfaceProbe.gd) to replace flat terrain assumptions with authoritative world-space geometry queries. A cornerstone of this architecture is **spline-free edge discovery (`find_edge_near`)**—allowing the skate deck to dynamically locate architectural concrete ledges, rails, curbs, and coping without relying on hand-authored guide rails or author-time splines! Stage 2 focuses on capitalizing on this geometry probing to execute realistic grinds (truck axles locked on edges) and slides (wooden deck bottom sliding across edges).

---

## 🏗️ Technical Specifications & Target Mechanics

### 1. Spline-Free Ledge & Rail Discovery (`find_edge_near`)
- **Probing Philosophy:** When airborne or popping near an obstacle, `SurfaceProbe.gd` projects rays forward and downward to identify sharp normal transitions (where horizontal top ledge normal flips to a vertical face).
- **Edge Direction Vector:** Once an edge is localized, its directional alignment vector in 3D space becomes our target grinding path!

### 2. Truck Lock-In & Deck Slide Tolerances
- **Grinds (Truck Contact):**
  - **50-50 Grind:** Both front and rear trucks sit directly on the target edge.
  - **5-0 / Nosegrind:** Only the trailing (5-0) or leading (Nosegrind) truck contact axle (`manual_axle_z = ±0.225m`) locks onto the rail while thumbstick pitch holds the opposite truck elevated.
  - **Crooked / Smith / Feeble / Salad:** Angular yaw offsets ($\approx 20^\circ \to 35^\circ$) combined with manual pitch angles, pinning one truck axle while the deck edge presses against the rail side.
- **Slides (Deck Bottom Contact):**
  - **Board Slide / Lipslide:** Skater rotates body $90^\circ$ perpendicular to travel vector. The middle of the wooden deck (`SkateDeckMesh` underside at `Y = 0.0155m`) rests squarely on the edge.
  - **Nails/Tailslides:** Extreme ends of the deck (`Z = ±0.4m`) slide along the ledge edge at perpendicular orientation.

### 3. Frictional Scrubbing & Momentum Retention
- **Differentiation of Surfaces:**
  - **Truck Axles (Steel on Concrete/Iron):** Extremely low kinetic friction ($0.05 \to 0.10$ coefficient when waxed/metal). Retains cruising speed smoothly.
  - **Deck Underside (Wood on Concrete/Rail):** Slightly higher deceleration friction unless speed exceeds entry threshold.
- **Wash-Out vs. Hangup Protection:**
  - Exiting a grind requiring jumping off or rolling off the end of the detected ledge segment.
  - Failing to re-orient within $\pm 45^\circ$ forward/backward travel upon dropping from a board slide onto flat pavement triggers a wheel skid bail!

---

## 🔍 Open Design & Calibration Questions
1. **Snap Assistance vs. True Physics Magnetism:** How aggressively should truck axles "snap" or attract onto a detected ledge when falling within $\pm 10\text{ cm}$ of an edge? We want authentic physical skill while preventing micro-clippings.
2. **Balance Gauging:** Should long grinds (e.g., rails $> 5\text{m}$) introduce gradual lateral instability requiring subtle left/right thumbstick counter-balance, or remain steady until speed drops below a stall velocity ($< 1.0\text{ m/s}$)?
