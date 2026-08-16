# Bridge Configuration System — Engineering Reference

This is the formula/constant reference for the abutment + bridge cost-optimization
model implemented in this project's Prolog files. It documents **exactly what the
code computes**, not idealized textbook practice — where the code takes a shortcut,
hard-codes a value, or has a quirk that affects results, that is called out
explicitly in a "Code behavior" note rather than smoothed over.

Companion document: `rag_system_guide.md` describes the algorithm/search procedure
that uses these formulas to enumerate and cost full bridge configurations. Read
that one to see *when* each formula below is invoked and what choices branch the
search; read this one for the formula itself.

---

## Design Standards

| Topic | Reference |
|---|---|
| Bearing capacity | Canadian Foundation Engineering Manual (CFEM) 4th Ed., Section 10.2 (Vesic 1975 factors) |
| Settlement (strip footing) | CFEM 4th Ed., Section 11.3.4 |
| Active earth pressure | Coulomb (1776), as presented in Craig's Soil Mechanics |
| Retaining wall stability | Craig's Soil Mechanics, Section 6.6, Equations 6.16–6.17 |
| Live load / dynamic load allowance / lane factors | CHBDC (CSA S6), Clause 3.8.4.5.3 and Tables 3.5/3.6 |
| Sheet-pile embedment (D/H ratios) | Rule-of-thumb ratios from free-earth/fixed-earth support method results (Rankine/Coulomb theory) — **preliminary sizing only**, not a substitute for a stamped earth-pressure analysis |

---

## Units & Sign Conventions

- Elevations and lengths in metres; angles converted to radians only inside trig calls.
- Unit weights in kN/m³, pressures in kPa, forces/reactions in kN, moments in kN·m.
- Coordinate origin **X = 0** is the bridge centreline at the bottom-obstacle elevation.
  X is **negative** toward the embankment/approach side, increases toward the river.
- Inside the wall-design force system (`equilibrium/4`), forces and moments are
  computed for the **full roadway width Z** (`roadway_width`), not per linear metre
  of wall. `W`, `Pa`, and `BearingLoad` are all total kN over the whole wall length;
  dividing a resultant by `B × Z` converts back to a bearing pressure in kPa.
- **Code behavior:** wall friction angle δ (`DeltaDeg`) is hard-coded to `0` at
  every call site — the vertical component of active thrust, `PaV`, is always zero
  in practice even though the formula supports a nonzero δ.

---

## Site Geometry

### Key Elevations
| Parameter | Description |
|---|---|
| `approach_elevation` | Top of approach road / deck surface |
| `design_high_water_level` (DHWL) | Governs minimum bearing elevation |
| `bottom` | Lowest obstacle / scour reference elevation |
| Surface elevation | `BearingElev + DepthFromRatio` |
| Bearing elevation | `max(DHWL + 0.3, ApproachElev − DepthFromRatio)` |

### Bearing Depth Ratio
```
DepthFromRatio = max(BridgeLength / (N × 30), 1.5)   [m]
```
`N` = span count for this branch of the search. Ensures the bearing is at least
1.5 m below grade and a span-to-depth ratio of ~30. This is recomputed **twice**:
once from a rough initial bridge-length estimate (before any geometry exists, used
only to seed the search) and once more, identically, per `N` inside the main solve
loop (`compute_bearing_for_nspan`).

### Initial Bridge Length Estimate
Seeds the bearing-depth calc before abutment geometry is known; not the final length:
```
BridgeLength₀ = (ApproachElev − BottomElev) × 2 × 2 + HO − 6   [m]
```

### Bridge Length (final)
```
BridgeLength = HO + 2 × |XBearing|
```
`HO` = `hydraulic_opening` (natural channel width at bottom elevation). `XBearing`
is the X-coordinate of the `bearing_x` marker element (when a retaining wall itself
reaches the surface) **or** the midpoint of the `stub_abutment` element's two X
faces (when a stub sits above the wall/embankment).

---

## Soil Profile Model

Borehole data is entered as `soil_log1(Type, Density, TopElevation)` facts — each
entry describes the stratum **starting at** that elevation and extending down to
the next entry's elevation (standard "top-of-layer" borehole log convention).

**Building the working soil model, per solve attempt:**
1. Every `soil_log1/3` fact is copied to `soil_log/3` (the working/dynamic copy).
2. One synthetic entry is added: `soil_log(gravel, dense, SurfaceElev)`, where
   `SurfaceElev` is this branch's computed surface elevation. This models an
   engineered/compacted **dense gravel fill zone immediately under the pavement
   structure**, overriding whatever the natural log says in that interval — it does
   *not* replace the user's log, it just adds a boundary at the surface elevation.
3. `soil/3` samples are asserted every **1.5 m**, stepping down from the highest
   logged elevation (across all `soil_log` entries, natural + synthetic) to the
   lowest logged elevation, using the stratum lookup above for each step's Type/
   Density. One extra sample is asserted exactly at the lowest logged elevation if
   the 1.5 m stepping doesn't land on it precisely.
4. Only samples with `Elev > bottom` participate in the layer/geometry model —
   material at or below the site bottom elevation is excluded from the stack.

**Supported soil types**: `gravel`, `sand`, `silt`, `clay`, `rock`
**Density descriptors**: `loose`, `medium`, `dense`, `soft`, `firm`, `stiff`, `very_stiff`, `sound`, `hard`

### Friction Angles (°) — `friction_angle(SoilType, Density, PhiDeg)`
| Soil | loose | medium | dense/stiff | notes |
|---|---|---|---|---|
| rock (sound) | — | — | 50 | sliding interface only — verify site-specific |
| gravel | 30 | 32 | 36 | |
| sand | 30 | 32 | 36 | |
| clay | soft 15 | firm 25 | stiff 30 | |
| silt | 30 (all densities) | | | |
| organic_soils | 20 (all densities) | | | |

### Elastic Moduli (kPa) — `elastic_modulus(SoilType, Density, E)`
| Soil | Value(s) |
|---|---|
| rock | sound 30,000,000 · hard 3,000,000 · soft 500,000 |
| gravel | loose 50,000 · medium 100,000 · dense 150,000 |
| sand | loose 20,000 · medium 25,000 · dense 100,000 |
| silty_sand | loose 15,000 · dense 50,000 |
| clay | very_soft 1,000 · soft 5,000 · medium 20,000 · stiff 50,000 · very_stiff 150,000 |
| silt | soft 5,000 · stiff 40,000 |
| organic_soils | 500 (all densities) |

---

## Embankment / Wall Layer Classification

Each soil layer above `bottom` is classified bottom-to-top into a geometric type,
which then maps to a structural element type:

| Geometric type | Structural element | Meaning |
|---|---|---|
| `slope` | `embankment` | fill sloped freely, 2H:1V |
| `confined` | `retainment` | vertical face, wall required |
| `vertical` | `rock_face` | rock — always vertical, no wall needed |

**Rock** is always classified `vertical` (no choice).

**Gravel** classification depends on the layer immediately below it and two running
flags, `Pcon` (a `confined` choice has been made at some point) and `Pslp` (a
`slope` choice has been made):

| Condition | Result |
|---|---|
| `Pcon` set, previous layer was `confined` | choice: `slope` **or** `confined` |
| `Pcon` set, previous layer was `slope` | forced: `slope` |
| `Pslp` set, previous layer was `slope` | choice: `slope` **or** `confined` |
| `Pslp` set, previous layer was `confined` | forced: `confined` |
| no flag set yet (first gravel layer) | choice: `slope` (sets `Pslp`) **or** `confined` (sets `Pcon`) |

Every "choice" above is a genuine backtracking point — the search explores both
branches and produces a separate candidate geometry for each. Sand/silt/clay
strata are not currently classified by `layer_config` (only `rock` and `gravel`
have rules) — a soil log using those types alone would not compile.

### Bearing Point Placement (stub abutment)
Looking at the top two profile nodes (immediately below the road surface):
- Two consecutive `slope` layers → stub bearing offset = surface X **+ 3.0 m**
- `slope` directly above `confined`/`vertical` → offset = surface X **+ 1.5 m**
- Anything else (top layer is `confined` or `vertical`) → **no stub**; the
  retaining wall itself carries the bearing seat and reaches the true surface.

---

## Retaining Wall Types & Selection

| Type | When selectable | Pricing method |
|---|---|---|
| `concrete_gravity` | Always | Volume |
| `timber_crib` | Always | Volume |
| `mse_wall` | Only when the wall does **not** reach the true road surface | Volume |
| `gabion_block` | Only when the wall does **not** reach the true road surface | Volume |
| `sheet_piling` | Only when the wall does **not** reach the true road surface (never listed in `wall_type_at_surface/1`) | Area |

`wall_type_at_surface/1` (only `concrete_gravity`, `timber_crib`) governs which
types are tried when a retainment element's top elevation equals the true surface
elevation; otherwise all five types in `retaining_wall_type/1` are tried, in that
declared order. When a wall **does** reach the surface, it also carries the girder
bearing reaction (`bearing_x_load`) and a `bearing_x` marker element is added for
bridge-length purposes.

---

## Frost Protection

Applies to gravity-type walls only (not sheet piling, which uses embedment sizing
instead — see below). Extends the wall base below its nominal `BotElev`:

| Wall position | Adjustment |
|---|---|
| Base is **above** the riverbed (`BotElev > bottom`) | Diagonal step at slope `atan(0.5)` (~26.57°, i.e. the 2:1 embankment slope angle): vertical penetration `Df·cos(atan0.5) ≈ 0.894·Df`, horizontal shift `Df·sin(atan0.5) ≈ 0.447·Df` toward the embankment |
| Base is **at or below** the riverbed | Straight vertical drop of the full frost depth `Df`, no horizontal shift |

`Df` = `frost_depth_for_wall(WallType)`:
| Wall type | Frost depth |
|---|---|
| `concrete_gravity` | site `frost_depth` fact (default 2 m) |
| `mse_wall`, `timber_crib`, `gabion_block`, `sheet_piling` | fixed 0.4 m |

**Rock refusal cap:** the theoretical frost-penetration depth above is passed
through `capped_penetration_depth/3`, which prevents the base from being driven
into sound rock:
- If the wall's starting elevation is **already on rock** → penetration is capped
  to a nominal **key-in depth of 0.5 m** (`rock_key_depth`) regardless of the
  theoretical value.
- If rock's top lies **within** the theoretical penetration zone → penetration is
  capped to (distance down to the rock surface) + 0.5 m key-in.
- If no rock is encountered in that zone → the full theoretical depth is used.

This same capping function (and the same 0.5 m key-in) is reused for the "extend"
scour-mitigation method below — a gravity footing can always bear directly on rock
with a nominal key-in; it never needs to be blocked outright the way a driven
sheet pile does.

---

## Scour Protection (river crossings only)

Only active when `obstacle_type(river)` and the wall's base sits **at or below**
the site bottom (riverbed) elevation. Two rules apply first, then the mitigation
choice:

1. **Not a river, or wall base is above the riverbed** → no scour protection needed.
2. **Riverbed founds directly on rock** (`soil_class_at_elev(bottom, rock)`) →
   also no scour protection needed for *any* wall type — rock is inherently
   scour-resistant, nothing erodible to protect. This is also what makes
   `mse_wall`/`gabion_block`/`timber_crib` viable at zero rock depth below the
   riverbed — they'd otherwise be blocked outright by an unachievable sheet-pile
   embedment requirement (see below) despite not actually needing protection.
3. Otherwise, the search tries every mitigation method permitted for that wall
   type via `wall_scour_mitigation(WallType, Method)` as separate candidate
   branches:

| Wall type | Permitted methods |
|---|---|
| `concrete_gravity` | `extend`, `sheet_pile` |
| `mse_wall` | `sheet_pile` only |
| `timber_crib` | `sheet_pile` only |
| `gabion_block` | `sheet_pile`, `extend` |

- **`extend`**: the wall base is driven down to `scour_depth` (default 1.5 m)
  below the riverbed, capped by the same rock-refusal rule as frost protection
  (nominal 0.5 m key-in if rock is encountered). Adds one `rip_rap` element.
- **`sheet_pile`**: a `sheet_piling` element is added at the wall toe, penetrating
  `sheet_pile_depth` (default 4.0 m) below the riverbed. The wall's own base stays
  at frost depth (unaffected). Adds a `sheet_piling` element **and** a `rip_rap`
  element. Uses `sheet_pile_penetration_depth/3` — see below, this **fails
  outright** (no candidate) if rock blocks the full depth.

`rip_rap` element extent = `rip_rap_extent` (default 5.0 m) from the wall face,
regardless of mitigation method.

---

## Sheet-Pile Wall Design (D/H rule-of-thumb)

`sheet_piling` is a fully separate structural path from the gravity-wall design
below — it is a cantilevered driven section, sized purely by an embedment-depth
ratio, with **no** base-width search, no overturning/sliding/eccentricity check,
no settlement or bearing-capacity check, and **no pile fallback** (a driven sheet
pile can't be rock-socketed the way a drilled/driven bearing pile can).

```
H       = TopElev − BottomElev                     (retained/exposed height)
Ratio   = d_h_ratio(Support, SoilClass)             (table below)
Theoretical = Ratio × H × embedment_fos_factor      (FOS = 1.2)
Dpenet  = sheet_pile_penetration_depth(BottomElev, Theoretical)
```
`Support` = `wall_support_type(sheet_piling, cantilever)` — only cantilever
(unanchored) sheet-pile walls are modeled currently; anchored ratios exist in the
table for a future tied-back wall type but are not reachable today.

`SoilClass` comes from `soil_class_map(Type, Density, Class)` applied to the soil
sample at `BottomElev`:

| Borehole type/density | Class |
|---|---|
| gravel loose | loose_granular |
| gravel medium | medium_granular |
| gravel dense | dense_granular |
| clay soft, clay medium | soft_clay (table groups these together) |
| clay stiff | stiff_clay |
| rock sound | rock (handled separately — see below) |

### D/H Ratio Table
| Support | loose_granular | medium_granular | dense_granular | soft_clay | stiff_clay |
|---|---|---|---|---|---|
| cantilever | 2.0 | 1.75 | 1.5 | 2.5 | 2.0 |
| anchored *(not reachable yet)* | 1.0 | 0.85 | 0.7 | 1.25 | 1.75 |

**Rock refusal — hard failure, not a cap:** unlike gravity-footing frost/scour
penetration, a driven sheet pile cannot gain any embedment into rock (no
predrilling/socketing). If the founding elevation is already on rock, or rock's
top lies anywhere within the theoretical penetration zone, `sheet_pile_penetration_depth/3`
simply **fails** — there is no valid sheet-pile design at that location, and the
search backs off to another wall type.

**Not modeled** (flagged in the source as future work): groundwater differential
across the wall, surcharge loads near the wall top, and base/heave stability for
soft clay (Terzaghi basal stability). None of these can be sized from a ratio
alone.

---

## Gravity Wall Stability Design

Applies to `concrete_gravity`, `timber_crib`, `mse_wall`, `gabion_block` (every
wall type **except** `sheet_piling`), and to the `stub_abutment` element (always
treated as `concrete_gravity`).

### Search
Iterates base width `B` starting at `H/4`, in **0.5 m increments**, up to 20 steps
(`B` up to `H/4 + 10 m`). The **first** `B` that passes every check below is
accepted — this is a committed choice (Prolog cut), not a minimization search
over all passing widths, though since `B` increases monotonically the first
passing value is also the narrowest, i.e. cheapest by volume/area.

### Active Earth Pressure (Coulomb)
```
Ka = [ sin(α−φ) / (sin α · (√sin(α+δ) + √(sin(φ+δ)·sin(φ−β)/sin(α−β))) ) ]²
Pa = 0.5 × Ka × γ × Z × H²          (Z = roadway_width — total load over full wall length)
PaH = Pa × cos δ,   PaV = Pa × sin δ
```
- α = 90° (vertical wall, always)
- β = 26.6° when the element **above** the wall is embankment (sloped backfill),
  else 0° (level backfill)
- δ = 0° always (see Units note above) → **PaV is always 0** in the current model
- φ = friction angle of the soil sample *at or above* the wall's `BotElev`
  (`soil_at_or_above/3` — nearest sample elevation ≥ BotElev)
- γ = **18 kN/m³**

> **Code behavior — dead configuration fact:** `site_facts.pl` declares
> `soil_gamma(20)`, but it is never consulted. The earth-pressure and
> bearing-capacity calculations both live inside the `abut_tree_gravity` Prolog
> *module*, which defines its own **local** `soil_gamma(18)` fact — Prolog module
> resolution uses that local fact instead of the one in `site_facts.pl` for every
> call inside that module, regardless of what calls into it. **To change the
> retained-soil unit weight actually used in wall design, edit `abut_tree_gravity.pl`,
> not `site_facts.pl`.** (`wall_gamma` happens not to have this problem — both
> copies are 24 kN/m³.)

### Wall Self-Weight and Applied Forces
```
W  = B × H × wall_gamma(24) × Z              (total self-weight, full wall length)
```
Three forces act on the wall (all totals over the full length `Z`):
1. Active earth thrust: `PaH` horizontal at height `H/3` above the base, applied
   at the horizontal position `X = −B/2` relative to wall centreline.
2. Self-weight `W`, downward, at the wall centreline (`X = 0`), height `H/2`.
3. Bearing reaction `BearingLoad` (0 if this wall doesn't carry `bearing_x_load`),
   downward, at `X = B/2 − Dbx` and the top of the wall (height `H`). `Dbx` is a
   fixed offset from the toe (0.6 m for a retaining wall that itself reaches the
   surface, or `B/2` — i.e. wall centreline — when `Dbx` isn't a positive value,
   as for a stub abutment where `Dbx = −10` is passed as a sentinel).

### Stability Checks (Craig s.6.6)
Moments taken about the **toe** (`X = B/2` in the wall's local frame):
```
Mr = |moment of (self-weight + bearing load + PaV) about the toe|   (resisting)
Mo = |moment of PaH about the toe|                                   (overturning)
FS_overturning = Mr / Mo   ≥ 2.0
```
```
V  = |total vertical reaction| (self-weight + bearing load + PaV, taken about the toe)
FS_sliding = (V × tan φ) / PaH   ≥ 1.5
```
φ here is the same `soil_at_or_above(BotElev)` friction angle used for Ka (the
code does not distinguish a separate base-sliding friction angle from the
retained-soil friction angle — both use the identical lookup at `BotElev`).

**Eccentricity** (about wall centreline, X = 0):
```
E = |M / V|
```
> **Code behavior — check present but not enforced:** `E` is computed and used
> downstream in the settlement calc (`B' = B − 2E`), but the conventional
> "middle-third" gate `E ≤ B/6` exists only as a comment in the source — it is
> **not** an active pass/fail condition. A design can be accepted with the
> resultant outside the middle third as long as overturning/sliding/settlement/
> bearing pass.

### Settlement Check (CFEM 4th s.11.3.4)
```
B'  = B − 2E                                      (effective width)
Qa  = V / B' / Z                                   (net bearing pressure, kPa)
Hr  = depth_to_rock(BotElev)                        (0 if already on rock; 999 = "no rock found")
Es  = elastic_modulus(soil at BotElev) / Defact      (Defact = 2.0 if the element below the wall is
                                                       embankment/sloped, else 1.0 — softer effective
                                                       stiffness assumed on a slope)
Is  = influence_factor(Hr / B')                      (table below)
S   = Qa × B' × Is / Es × 1000                       [mm]
```
Allowable settlement (`allowable_settlement_for_wall`): **25 mm** for
`concrete_gravity`; **50 mm** for `mse_wall`, `timber_crib`, `gabion_block`,
`sheet_piling` (sheet piling's value is unused since it never reaches this check).

**Influence factor table** (H/B → I_s, linear interpolation, fails outside range):
| H/B | 0 | 0.10 | 0.25 | 0.50 | 1.00 | 2.50 | 5.00 | 1000 |
|---|---|---|---|---|---|---|---|---|
| I_s | 0.00 | 0.90 | 0.95 | 1.00 | 1.10 | 1.30 | 1.50 | 1.80 |

(`0` and `1000` are sentinels: `H/B → 0` means rock right at the footing base, no
compressible material, zero settlement; `H/B → 1000` approximates the H/B → ∞
asymptote of 1.8.)

### Bearing Capacity Check (CFEM 4th s.10.2, Vesic 1975)
```
qu = c·Nc·Sc + q·Nq·Sq + 0.5·γ·B'·Nγ·Sγ
```
Called with **`c = 0`** (cohesionless assumption, no cohesion term regardless of
the actual soil) and **`D = 0`** (no embedment surcharge, so `q = γ·D = 0`).

> **Code behavior — two of three terms are always zero.** With `c = 0` and `D = 0`
> hard-coded at the call site, the cohesion term and surcharge term both vanish
> identically — the entire bearing capacity in this model reduces to
> `qu = 0.5 × γ × B' × Nγ × Sγ`, the self-weight term alone. Shape/depth/slope
> factors for the other two terms are still computed by `ultimate_bearing_capacity/8`
> (it's a general-purpose predicate) but have no effect on the result here.

Other inputs: `L = 3B` (strip-like assumption, not infinite), `φ` and `γ` are the
same soil-at-`BotElev` lookup used above (γ = **18 kN/m³**, same dead-config note
as earth pressure), slope angle `BetaDeg` = 26.6° if the element below the wall is
embankment else 0° (same `Defact`-triggering condition as the settlement check).

**Bearing factors** (Nc, Nq, Nγ): standard Vesic form for φ ≠ 0; special-cased for
φ = 0 (undrained) with `Nc = 5.14`, `Nq = 1`. Shape/depth/slope modification
factors follow Vesic (1975), assuming no load inclination and no base tilt.

Check: `Qa < Qr` (no explicit factor of safety multiplier beyond the ratio itself
— the 25/50 mm settlement limit is what typically governs for granular soils).

---

## Pile Foundation (Fallback)

Offered as a **separate candidate alongside** the gravity footing (not only when
the footing fails) — but **only for `concrete_gravity`** walls and stub abutments;
every other wall type has no pile alternative. The search backtracks over the
same base-width sequence as the footing (`B` from `H/4` in 0.5 m steps), and for
each `B` searches pile configurations; the **first** `B` that yields any valid
pile configuration is accepted (committed via cut).

### Pile Cap Forces
At each candidate `B`, wall geometry/forces are recomputed identically to the
gravity-wall case (same Ka, Pa, W formulas above), then resolved to a resultant
at the cap centre: `Pcf` (vertical), `Mcf` (moment), `Vcf` (horizontal/lateral).

### Row Configuration Search
Tries 1, 2, or 3 rows of piles within the cap width `B`:

| Rows | Pile count candidates | Row positions |
|---|---|---|
| 1 | `n1_range` = [4,6,8,10,12,14] | single row at `B/2` |
| 2 | row 1: `n1_range`, row 2: `n2_range` = [4,6,8,10,12], with `N1 ≥ N2` | `X1 = x1min` (0.450 m), `X2 = B − x1min`, requires `B ≥ 2×x1min + 3×Dia` |
| 3 | row 1: `n1_range` (`N1 ≥ N2`), row 2/3: `n2_range`/`n3_range` = [4,6,8,10,12] | `X1 = x1min`; `X2 = X1 + Dx` for `Dx ∈ {3,4,5,6}×Dia`; `X3` chosen so `X3 − X2 > 3×Dia`, `X3 = B − x1min − Off` for `Off ∈ {0, 0.5}` |

Pile diameter `Dia` is tried from the catalogue `dias = [0.3, 0.4, 0.5, 0.6]` m.

**Single-row moment restriction:** a 1-row config is only offered when
`|Mcf| < pile_mc_threshold` (180 kN·m) — too much moment for a single row to resist.

**Transverse fit** (across roadway width `Z`, independent of the longitudinal
row spacing above): for a row of `N` piles,
```
RequiredWidth = 2 × transverse_edge_factor(1.5) × Dia + (N−1) × transverse_spacing_factor(4) × Dia ≤ Z
```

### Load Distribution (elastic pile-group method)
```
Xc  = (N1·X1 + N2·X2 + N3·X3) / Nt                  (centroid)
Ri  = (B/2 − Xi) − (B/2 − Xc)                        (moment arm of row i about centroid)
Mc  = Mcf − Pcf × (B/2 − Xc)                          (moment corrected for centroid offset)
Pi  = Pcf/Nt  +  Mc·Ri / ΣNj·Rj²                      (row 1 always +; rows 2/3 use their own Ri sign)
```
Row 1 (1 row only): `P1 = Pcf/Nt` (no moment term). Capacity: `P1, P2, P3 < pile_pmax`
(900 kN); rows 2/3 additionally required `> 0` (a genuinely under-loaded extra row
is rejected, not merely capped — but rows that don't exist for the given row count
are exempted from this positivity check).

### Inclined Piles & Lateral Load
Outer rows are driven at an inclination `pile_incl` = 4 (rise:run 1:4). How many
piles per row are inclined depends on row count:

| Rows | Inclined in row 1 (`Ni1`) | Inclined in row 2 (`Ni2`) | Row 3 |
|---|---|---|---|
| 1 | `N1 // 2` (half) | — | — |
| 2 | all of `N1` | 0 (none) | — |
| 3 | all of `N1` | all of `N2` | always vertical only |

```
Ht = (P1×Ni1 + P2×Ni2) / pile_incl        (lateral resistance from inclined piles)
Hi = (Vcf − Ht) / Nt                        (residual lateral load per vertical pile)
```

**Row-spacing group effect:** closely spaced rows shadow each other under lateral
load. The governing ratio is the smallest row-to-row spacing (in pile diameters);
for 3 rows, `min((X2−X1)/Dia, (X3−X2)/Dia)`.
```
GroupMult = clamp(0.2 × Ratio − 0.2,  0, 1.0)     (0 at 1D spacing, 1.0 at 6D+)
Hlat = pile_hlat(80 kN) × GroupMult
```
Check: `Hi < Hlat`.

### Selecting the Best Configuration
Among all row/count/spacing/diameter combinations that pass every check above:
1. Minimize total pile count `Nt`.
2. Among those, minimize the maximum row-1 load `P1`.

### Pile Length & Rock Socketing
`PileLength = depth_to_rock(BotElev)` — how far the pile can be driven before
meeting a logged rock stratum. When `PileLength < rock_socket_min_length` (5 m),
there isn't enough embedded shaft length left to mobilize lateral resistance
through soil passive pressure alone, so the pile is priced as **rock-socketed**:
adds `rock_socket_length` (3 m) drilled into rock, at `rock_socket_cost_multiplier`
(3×) the normal per-metre rate. See Cost Model below.

---

## Superstructure

### Span Configuration Rules
Spans must cover the bridge length but not exceed it by more than 3 m (tight-fit
rule). For each girder type (tried in catalogue order — see below), the search
commits to the **first** (shortest) qualifying stock length; it does not enumerate
every stock length that would fit, only one candidate per girder type.

| N | Rule |
|---|---|
| 1 | `L ≥ BridgeLength`, `L < BridgeLength + 3` |
| 2 | both spans equal `L`; `2L ≥ BridgeLength`, `2L < BridgeLength + 3` |
| 3 | symmetric `[L1, L2, L1]`, `L2 ≥ L1`; `2L1+L2 ≥ BridgeLength`, `2L1+L2 < BridgeLength+3` (first `(L1,L2)` pair found, `L1` outer / `L2` inner, both in catalogue order) |

### Girder Types
| Type | Tributary width (m) | Stock lengths (m) | Cost basis |
|---|---|---|---|
| `voided_precast` | 1.2 | 8, 10, 12, 14 | flat $2,000/m/girder |
| `next_beams` | 2.5 | 9, 11, 13, 15, 17, 19 | flat $5,000/m/girder |
| `steel_beams` | 2.5 (2 beams + deck) | 20–70 in **1 m** increments | priced from first principles (steel mass + deck concrete volume) |

Number of girders per span: `⌈ roadway_width / tributary_width ⌉`.

Girder types are tried **in declaration order** — `voided_precast` first, then
`next_beams`, then `steel_beams` — matching "cheapest/simplest first," but the
search still yields **all three** as separate candidates (whichever have a
feasible stock length), not just the first that succeeds; `solve_all`'s downstream
cost sort is what actually picks the cheapest.

### Girder Self-Weight
| Type | Unit weight |
|---|---|
| `voided_precast` | 11.4 kN/m (flat, composite beam+deck) |
| `next_beams` | 23.4 kN/m (flat, composite beam+deck) |
| `steel_beams` | `SteelArea × steel_density(79) + slab_thickness(0.2) × tributary_width(2.5) × concrete_density(24)`, where `SteelArea = 3 × steel_web_thickness(0.016) × depth(1.0)` (assumed I-section: web + 2 equal flanges) |

### Interior Piers
One `pipe_pile_bent` pier per interior support (`NPiers = N − 1`). Height =
`BearingElev − BottomElev`. No structural design/sizing beyond this — pricing is
a flat rate (see below).

---

## Loads

### Dead Load (abutment/pier reactions)
Each span treated as an independent simply-supported run. An end abutment carries
half the dead weight of the one span framing into it; an interior pier carries
half of *each* of its two adjacent spans.
```
Reaction = girder_unit_weight × NGirders × SpanLength / 2
```
Used (at 1.2× factor, see below) as part of the preliminary `bearing_x_load`
estimate — **not** recomputed with the final designed span length; see the system
guide for when this estimate is taken.

### Live Load (CHBDC truck model)
5-axle design truck: weights `[50, 125, 125, 175, 150]` kN, spacings
`[3.6, 1.2, 6.6, 6.6]` m between successive axles.

1. Enumerate every **contiguous axle group** (front-trim × back-trim combinations,
   from the single front axle up to the full 5-axle truck).
2. For each group that fits on the span (`BridgeLength ≥ group length`), compute
   the simply-supported reaction with the group positioned two ways — first axle
   at the span start, then last axle at the span end — and take the larger.
3. Dynamic load allowance (`DLA`, CHBDC Cl. 3.8.4.5.3):
   | Axles in governing group | DLA |
   |---|---|
   | 1 | 0.40 |
   | 2, or exactly axles [1,2,3] | 0.30 |
   | any other 3+ | 0.25 |
4. Governing group = the one maximizing `StaticReaction × (1 + DLA)` — a smaller
   group with a larger DLA can beat a bigger group with a smaller one.
5. Scale by design lanes and multi-lane factor (CHBDC Tables 3.5/3.6), using a
   **separate** `deck_width` fact (currently 10 m):

   | `deck_width` ≤ | Design lanes N |
   |---|---|
   | 6.0 | 1 |
   | 10.0 | 2 |
   | 13.5 | 3 |
   | 17.0 | 4 |
   | 20.5 | 5 |
   | 24.0 | 6 |
   | 27.5 | 7 |
   | (else) | 8 |

   | N | Multi-lane factor |
   |---|---|
   | 1 | 1.00 |
   | 2 | 0.90 |
   | 3 | 0.80 |
   | 4 | 0.70 |
   | 5 | 0.60 |
   | ≥6 | 0.55 |

   ```
   LiveLoadReaction = GoverningFactoredReaction × N × MultiLaneFactor
   ```

> **Code behavior — separate, unsynced fact.** `Live_load.pl` defines its own
> `deck_width(10)` fact, distinct from `site_facts.pl`'s `roadway_width(10)`. They
> currently match by coincidence. **If you change the roadway width for a new
> site, you must also update `deck_width` in `Live_load.pl`, or the lane count
> will silently stay computed against the old width.**

### Preliminary `bearing_x_load` Estimate
Computed once per span-count branch, **before** any wall geometry is designed
(breaking the circular dependency: wall design needs the bearing load, but the
bearing load ideally depends on final span length, which depends on the designed
wall geometry):
```
SpanEstimate = BridgeLength₀ / N
GirderType    = first girder_type/1 with any catalogue length ≥ SpanEstimate
DeadLoad      = girder_unit_weight × NGirders × SpanEstimate / 2
LiveLoad      = live_load_abutment_reaction(SpanEstimate)
bearing_x_load = 1.2 × DeadLoad + 1.7 × LiveLoad
```
This value is then used, frozen, for every wall/stub design in that N-branch —
it is not re-derived from the final, as-designed span length. Also note the
1.2 dead-load factor is applied uniformly to all girder types (including the
steel portion of `steel_beams` and the not-yet-modeled asphalt wearing surface);
the source flags this as a simplification pending a proper per-material split
(steel 1.1 / concrete 1.2 / asphalt 1.5).

---

## Cost Model

All costs below are **both abutments combined** (× 2) except piers and pile items,
which already sum both abutments' piles into one total. Every line item is a
`priced(Elem, Label, Cost)` entry; the solution total is their sum.

| Element | Formula |
|---|---|
| Girders (`voided_precast`/`next_beams`) | `girder_cost_per_m × TotalSpanLength × NGirders` |
| Girders (`steel_beams`) — steel | `SteelVolume × steel_density_kgm3(7850) × steel_unit_cost($10/kg)`, `SteelVolume = SteelArea × TotalSpanLength × NGirders` |
| Girders (`steel_beams`) — deck | `slab_thickness(0.2) × RoadwayWidth × TotalSpanLength × deck_concrete_unit_cost($2400/m³)` (own line item, full-width pour, not per-girder) |
| Concrete gravity **retainment** wall, `B ≤ 2.5 m` | `2 × H × B × RW × $2,000/m³` |
| Concrete gravity **retainment** wall, `B > 2.5 m` | `2 × (1.5B + (H−1.5)×1.5) × RW × Rate` (T-section: footing 1.5×B + stem (H−1.5)×1.5) |
| **Stub abutment** (always `concrete_gravity`) | `2 × H × B × RW × Rate` — **always rectangular**, regardless of `B`; the T-section discount only applies to `retainment`-type elements, never to the stub |
| `mse_wall` / `gabion_block` / `timber_crib` **retainment** | `2 × H × B × RW × Rate` (all priced by **volume** — see rates below) |
| `sheet_piling` | `2 × H × RW × $1,100/m²` (area) |
| `rip_rap` | `2 × Extent × RW × $150/m²` (area) |
| Embankment | `2 × 30 × RW × H` (flat rate, treated as $/m² of the RW×H cross-section) |
| Piles (normal) | `2 × NPiles × PileLength × $600/pile/m` |
| Piles (rock-socketed, `PileLength < 5 m`) | `2 × NPiles × (PileLength + 3 m socket) × ($600 × 3)/pile/m` |
| Piers | `NPiers × $20,000/m width × RoadwayWidth` |

### Wall Unit Rates (`wall_cost_props`)
| Wall type | Method | Rate |
|---|---|---|
| `concrete_gravity` | volume | $2,000/m³ (incl. ~$500/m³ reinforcing) |
| `stub_abutment` | volume | $2,000/m³ |
| `timber_crib` | volume | $2,000/m³ |
| `mse_wall` | volume | $600/m³ (incl. facing panels, geogrid, select backfill) |
| `gabion_block` | volume | $450/m³ (incl. basket + stone fill) |
| `sheet_piling` | area | $1,100/m² (supply + drive) |
| `rip_rap` | area | $150/m² (supply + place) |

Rates are in CAD, illustrative/calibrated placeholders — see `price_list.pl`
comments for the calibration basis of the MSE and gabion rates specifically
(both back-calculated to match prior $/m² face-area estimates at representative
B/H ratios).

`W` = roadway width, `H` = wall height, `B` = base width, `RW` = `roadway_width`
(same value, used interchangeably above).

---

## Known Assumptions, Limitations, and Code-Behavior Notes

Modeling assumptions (by design):
- Single borehole: soil profile is uniform across the site (no transverse variation).
- 1:2 slope (26.6°) assumed for all embankment fills and sloped surcharge/backfill.
- No seismic loading; no live-load surcharge on retained soil.
- Bearing capacity `L` assumed as `3B` (not an infinite strip).
- Both abutments assumed identical (symmetric bridge); all costs doubled from a
  single-abutment design rather than designing each independently.
- Pile design uses the static elastic pile-group method only (no dynamic capacity,
  no group settlement check).
- Sheet-pile embedment is preliminary rule-of-thumb sizing only (see that section);
  groundwater differential, surcharge, and basal stability are not modeled.

Non-obvious current code behavior (things a naive re-implementation would get
wrong by "fixing" or by following an outdated comment):
- **`soil_gamma(20)` in `site_facts.pl` is dead** — wall design actually uses
  18 kN/m³ from a module-local fact in `abut_tree_gravity.pl`. Edit that file to
  change it.
- **Eccentricity's `E ≤ B/6` middle-third check is computed but not enforced** —
  only overturning, sliding, settlement, and bearing capacity gate acceptance.
- **Bearing capacity's cohesion and surcharge terms are always zero** (`c=0`,
  `D=0` hard-coded) — only the self-weight term `0.5·γ·B'·Nγ·Sγ` ever contributes.
- **`deck_width` (live load) and `roadway_width` (everything else) are separate,
  unsynced facts** — currently equal by coincidence, not by reference.
- **`bearing_x_load` is a frozen preliminary estimate**, computed once from the
  rough initial bridge length before geometry/spans are finalized, and never
  recomputed against the actual final span length.
- **The stub abutment is always priced as a plain rectangle**, even past `B > 2.5 m`
  where a `retainment`-type concrete gravity wall would switch to the cheaper
  T-section formula.
- **The same soil sample (`soil_at_or_above(BotElev)`) is reused for both the
  retained-soil friction angle (Ka) and the founding-soil friction angle
  (bearing capacity)** — the model does not distinguish backfill soil from
  founding soil.
