# Bridge Configuration System — Engineering Reference

## Design Standards

| Topic | Reference |
|---|---|
| Bearing capacity | Canadian Foundation Engineering Manual (CFEM) 4th Ed., Section 10.2 |
| Settlement (strip footing) | CFEM 4th Ed., Section 11.3.4 |
| Active earth pressure | Coulomb (1776), as presented in Craig's Soil Mechanics |
| Retaining wall stability | Craig's Soil Mechanics, Section 6.6, Equations 6.16–6.17 |
| Bearing capacity factors | Vesic (1975) — shape, depth, slope modification factors |

---

## Site Geometry

### Coordinate System
- Origin (X = 0): bridge centreline at bottom obstacle elevation
- X increases toward river, decreases (negative) into embankment
- All elevations in metres above an arbitrary datum

### Key Elevations
| Parameter | Fact | Description |
|---|---|---|
| `approach_elevation` | 100 m (example) | Top of approach road / deck surface |
| `design_high_water_level` | DHWL | Governs minimum bearing elevation |
| `bottom` | 93 m (example) | Lowest obstacle / scour elevation |
| Surface elevation | Computed | `BearingElev + DepthFromRatio` |
| Bearing elevation | Computed | `max(DHWL + 0.3, ApproachElev − DepthFromRatio)` |

### Bearing Depth Ratio
The girder soffit depth below approach grade:
```
DepthFromRatio = max(BridgeLength / (N × 30), 1.5)   [m]
```
Ensures the bearing is always at least 1.5 m below grade and maintains a span-to-depth ratio of approximately 30.

### Initial Bridge Length Estimate
Used only to seed the bearing depth calculation before abutment geometry is known:
```
BridgeLength₀ = (ApproachElev − BottomElev) × 2 × 2 + HO − 6   [m]
```
The final bridge length is computed from the **designed** abutment geometry.

### Bridge Length (final)
```
BridgeLength = HO + 2 × |XBearing|
```
Where `XBearing` is the X coordinate of the bearing seat (`bearing_x` element) or centre of stub abutment. `HO` = hydraulic opening (natural channel width at bottom elevation).

---

## Soil Profile Model

Borehole data is entered as `soil_log1(Type, Density, TopElevation)` facts in `site_facts`. The system interpolates soil samples at 1.5 m depth intervals using `assert_soil_from_logs`. Only soils above the `bottom` elevation participate in profile building.

**Supported soil types**: `gravel`, `sand`, `silt`, `clay`, `rock`  
**Density descriptors**: `loose`, `medium`, `dense`, `soft`, `firm`, `stiff`, `very_stiff`, `sound`, `hard`

---

## Embankment Geometry — Layer Configuration

Each soil layer above `bottom` is assigned a configuration type:

| Type | Condition | X change per layer |
|---|---|---|
| `slope` | Gravel / sand — fill slopes freely | `ΔX = −2 × Height` (1:2 slope) |
| `confined` | Gravel / sand — retained | `ΔX = 0` (vertical face, wall required) |
| `vertical` | Rock | `ΔX = 0` (rock face) |

The solver backtracks over slope/confined choices per gravel layer, producing multiple geometry variants. Once a choice is made (slope or confined) the subsequent layers follow consistent rules tracked by flags `Pslp` / `Pcon`.

### Bearing Point Placement
After the profile is built, if the topmost layer is a slope:
- Two consecutive slope layers → bearing X = surface X + 3 m
- Slope above confined/vertical → bearing X = surface X + 1.5 m

The bearing point defines where the stub abutment or bearing seat is placed.

---

## Retaining Wall Design

### Wall Types and Selection Rules

| Type | When selectable | Pricing |
|---|---|---|
| `concrete_gravity` | Always; required when wall reaches surface | Volume (H × B × W) |
| `timber_crib` | Always; permitted when wall reaches surface | Volume (H × B × W) |
| `mse_wall` | Wall does NOT reach surface | Area (H × W) |
| `gabion_block` | Wall does NOT reach surface | Area (H × W) |

When the retaining wall reaches the surface elevation, it also carries the girder bearing load (`bearing_x_load`) and a `bearing_x` marker element is added to `PropElem`.

### Frost Protection
The wall base is extended below `BotElev` for frost:
- If wall is above riverbed: base shifted diagonally at atan(0.5) slope by `frost_depth`
- If wall is at or below riverbed: base dropped vertically by `frost_depth`
- MSE, timber crib, gabion: 0.4 m frost depth regardless of `frost_depth` site fact

### Base Width Search
`design_wall` iterates base width B starting at H/4, in 0.5 m increments, until all checks pass. First valid B is accepted (minimum base width).

### Stability Checks (Craig s.6.6)

All moments and forces are computed using the `equilibrium/4` predicate with three applied forces:
1. Active earth pressure resultant (Pa at H/3 above base)
2. Wall self-weight (W at base centre)
3. Bearing load (at bearing X offset from toe)

**Overturning**: `FS = Mr / Mo ≥ 2.0`  
**Sliding**: `FS = (V × tan φ) / PaH ≥ 1.5`

### Active Earth Pressure (Coulomb)
```
Ka = [ sin(α−φ) / (sin α × (√sin(α+δ) + √(sin(φ+δ)×sin(φ−β)/sin(α−β))))² ]
Pa = 0.5 × Ka × γ × W × H²
PaH = Pa × cos δ,   PaV = Pa × sin δ
```
- α = 90° (vertical wall)
- β = 26.6° for embankment backfill (1:2 slope), 0° for level backfill
- δ = 0° (smooth wall interface assumed)
- γ = retained soil unit weight (`soil_gamma`)

### Settlement Check (CFEM 4th s.11.3.4)
```
S = q × B' × Is / E   [mm]
```
- `q = Rcy / B' / W` — net bearing pressure (kPa)
- `B' = B − 2E` — effective width after eccentricity correction
- `Is` — influence factor interpolated from H/B ratio (strip footing table)
- `E` — elastic modulus of bearing soil (kPa), halved when on a slope
- Allowable settlement: 25 mm (concrete), 50 mm (MSE, crib, gabion)

### Bearing Capacity Check (CFEM 4th s.10.2)
```
qu = c·Nc·Sc + q·Nq·Sq + 0.5·γ·B'·Nγ·Sγ
```
Shape (Scs, Sqs, Sγs), depth (Scd, Sqd, Sγd), and slope (Scβ, Sqβ, Sγβ) factors after Vesic (1975). L = 3B assumed (strip-like footing, not infinite). Slope angle `BetaDeg` = 26.6° for embankment, 0° for level ground.

Bearing capacity check: `q < qu` (no factor of safety applied explicitly — the settlement check at 25 mm typically governs for granular soils).

---

## Pile Foundation (Fallback)

Activated automatically when `design_wall` fails for a `concrete_gravity` wall (settlement or bearing capacity exceeded for all B values).

### Pile Cap Layout
Piles are arranged in 1, 2, or 3 rows within the wall base width B. The solver minimises total pile count, then minimises maximum pile load P1.

**Load distribution** (elastic pile group method):
```
Pi = P/Nt ± M·Ri / ΣNj·Rj²
```
- P = total vertical load at cap centre
- M = moment corrected for centroid offset
- Ri = distance from pile row i to centroid

**Inclined piles**: outer rows inclined at 1:4 (rise:run). Inclined component resists lateral load:
```
Ht = (P1·Ni1 + P2·Ni2) / Incl
Hi = (Vcf − Ht) / Nt   [lateral load per vertical pile]
```

**Capacity limits** (from `site_facts`):
- `pile_pmax` = 900 kN — maximum vertical load per pile
- `pile_hlat` = 125 kN — maximum lateral load per vertical pile
- Tension limit: P2, P3 > −100 kN

---

## Superstructure

### Span Configuration Rules
- Spans must cover the bridge length but not exceed it by more than 3 m (tight fit rule)
- 2-span: both spans equal
- 3-span: symmetric (L1, L2, L1) with L2 ≥ L1

### Girder Types
| Type | Width (m) | Available lengths (m) | Cost ($/m/girder) |
|---|---|---|---|
| `voided_precast` | 1.2 | 8, 10, 12, 14 | 2,500 |
| `next_beams` | 2.5 | 9, 11, 13, 15, 17, 19 | 5,000 |
| `steel_beams` | 2.5 | 20–40 in 2.5 m steps | 5,000 |

Number of girders per span: `⌈ roadway_width / girder_width ⌉`

Solver tries `voided_precast` first (ordered by fact listing in `bridge_facts`).

### Interior Piers
One pier per interior support. Always `pipe_pile_bent` type.
```
PierCost = NPiers × 20,000 × roadway_width   [$]
```
Pier height = `BearingElev − BottomElev`.

---

## Cost Pricing Summary

All costs are **both abutments combined** (× 2) except piers.

| Element | Rate source | Method |
|---|---|---|
| Concrete gravity / stub (B ≤ 2.5 m) | 1,700 $/m³ | H × B × W × Rate × 2 |
| Concrete gravity (B > 2.5 m) | 1,700 $/m³ | (1.5B + (H−1.5)×1.5) × W × Rate × 2 |
| Timber crib | 2,000 $/m³ | H × B × W × Rate × 2 |
| MSE wall | 1,200 $/m² | H × W × Rate × 2 |
| Gabion block | 1,000 $/m² | H × W × Rate × 2 |
| Piles | 6,000 $/pile | NPiles × Rate × 2 |
| Embankment | flat rate | 2 × 30 × W × H |
| Piers | 20,000 $/m width | NPiers × Rate × W |
| Girders | varies $/m | TotalLength × NGirders × CostPerM |

Rates are in CAD. Sources noted in `bridge_facts`.

---

## Known Assumptions and Limitations

- Single borehole: soil profile is uniform across the site (no transverse variation)
- 1:2 slope assumed for all embankment fills (Coulomb β = 26.6°)
- Embankment above retaining wall: slope set at 1:2 (TopX = BotX − 2H)
- Concrete wall self-weight uses γ = 24 kN/m³; retained soil γ = 20 kN/m³
- No seismic loading
- No live load surcharge on retained soil
- No scour depth calculation (bottom elevation set manually)
- No water table correction for bearing capacity (single γ used)
- Settlement formula assumes uniform elastic layer of thickness H to rock
- Bearing capacity L assumed as 3B (not infinite strip)
- Both abutments assumed identical (symmetric bridge)
- Pile design uses static elastic group method only (no dynamic capacity)
