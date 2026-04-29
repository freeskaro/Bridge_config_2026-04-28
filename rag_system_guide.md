# Bridge Configuration System — Code & Architecture Guide

## Purpose

This SWI-Prolog system enumerates and costs bridge configurations for a specific site. Given soil borehole data, site geometry, and hydraulic constraints, it generates every valid combination of:

- Abutment / embankment geometry (slope or retained)
- Retaining wall type and dimensions
- Span count, girder type, and span lengths
- Interior pier configuration
- Itemised cost estimate

The entry point is `solve_all(Solutions)` in `prolog_bridge_config`, which returns a list of `solution/6` terms. Results are printed with `print_all_solutions(+Solutions)`.

---

## File Structure and Responsibilities

| File | Role |
|---|---|
| `site_facts` | **Edit per project.** Soil log, site elevations, hydraulic data, roadway width, wall type rules, pile parameters |
| `bridge_facts` | **Catalogue / price list.** Girder stock lengths, section properties, cost rates for walls, piers, piles |
| `Abut_config_facts` | Soil property tables: `friction_angle/3`, `elastic_modulus/3`, `elem_type/2` |
| `abut_soil_config_8` | Core geometry engine: soil sampling, profile building, element compilation, wall sizing |
| `abut_pile_fallback.pl` | Pile foundation fallback when footing fails; pile cap layout optimisation |
| `abut_tree_gravity` | Module: gravity wall stability checks (FS overturning, sliding, eccentricity, settlement, bearing capacity) |
| `Abut_tree_footing_def` | Module: elastic strip-footing settlement formula (CFEM 4th s.11.3.4) |
| `CFEM_4th_prolog_qu` | Module: ultimate bearing capacity (CFEM 4th s.10.2, Vesic factors) |
| `prolog_bridge_config` | Top-level solver: span selection, cost pricing, solution printing |

**Consult chain** (load order):
```
prolog_bridge_config
  ├── bridge_facts
  └── abut_soil_config_8
        ├── site_facts
        ├── abut_config_facts
        └── abut_pile_fallback
              ├── abut_tree_gravity (module)
              ├── Abut_tree_footing_def (module)
              └── CFEM_4th_prolog_qu (module)
```

Load the system by consulting `prolog_bridge_config` in SWI-Prolog.

---

## Key Data Structures

### Element term — `elem/7`
```prolog
elem(Type, BotX, BotElev, TopX, TopElev, B, WallType)
```
| Arg | Meaning |
|---|---|
| `Type` | `embankment`, `retainment`, `stub_abutment`, `bearing_x`, `piles` |
| `BotX` | X at bottom of element (m from bridge centreline, negative = embankment side) |
| `BotElev` | Elevation at bottom (m) |
| `TopX` | X at top of element (back face for walls) |
| `TopElev` | Elevation at top (m) |
| `B` | Base width (m); designed by `design_wall` for retainment/stub |
| `WallType` | `concrete_gravity`, `mse_wall`, `timber_crib`, `gabion_block`, or `none` |

**Pile element** has a different layout:
```prolog
elem(piles, RowCounts, Spacings, none, none, none, none)
%   RowCounts = [N1] or [N1,N2] or [N1,N2,N3]  — piles per row
%   Spacings  = [X1] or [X1,X2] or [X1,X2,X3]  — row X positions from cap front (m)
```

### Solution term — `solution/6`
```prolog
solution(NSpans, PropElem, BridgeLength, GirderType, SpanLengths, Piers)
```
| Arg | Meaning |
|---|---|
| `NSpans` | 1, 2, or 3 |
| `PropElem` | List of `elem/7` terms describing both abutments |
| `BridgeLength` | Total bridge length (m) |
| `GirderType` | `voided_precast`, `next_beams`, or `steel_beams` |
| `SpanLengths` | List of individual span lengths (m) |
| `Piers` | `piers(NPiers, Type, Height, BotElev, BearingElev)` |

### Priced item — `priced/3`
```prolog
priced(Elem, Label, Cost)
%   Label = human-readable atom describing the item
%   Cost  = $ (both abutments combined for wall/pile items)
```

---

## Execution Flow — `solve_one/1`

```
nspan(N)                          % try 1, 2, 3 spans
  → reset dynamic DB (retract_all_facts)
  → load soil log (assert_all_soil_logs + assert_soil_from_logs)
  → compute initial bridge length and bearing elevation
  → build_list: sorted soil layer list above bottom elevation
  → iter_depth: backtrack over slope/confined geometry combinations
      → compile_elements: translate profile points to elem/7 list
          → design_retain: size each wall (design_wall / pile_fallback)
              → propagate designed back-face X to embankment above
              → update stub abutment bearing position accordingly
  → bridge_length: compute from bearing_x or stub_abutment TopX
  → span_config: find girder type + lengths covering bridge length
  → pier_config: size interior piers
```

`findall(Sol, solve_one(Sol), Solutions)` collects all valid combinations.

---

## Geometry Conventions

- X = 0 at bridge centreline (river centreline)
- X is **negative** toward the embankment (approach road side)
- Elevations in metres; X coordinates in metres
- `BotX` of a wall = toe (river-facing face at base)
- `TopX` of a wall = back face (embankment-facing face at base)
- For non-MSE walls: `TopX = BotX − B`
- For MSE walls: `TopX = BotX − 1.5` (nominal setback)
- Stub abutment: centred on `BearingX`; `BotX = BearingX + B/2`, `TopX = BearingX − B/2`
- `bearing_x` element: marks the girder bearing seat position for bridge length calculation

---

## Identifying Abutment Types in a Solution

```prolog
% Earth-retaining abutment — has a retainment element
member(elem(retainment, _, _, _, _, _, WallType), PropElem)

% Full-height wall (reaches surface, has bearing seat above it)
member(elem(retainment, _, _, _, _, _, concrete_gravity), PropElem),
member(elem(bearing_x, _, _, _, _, _, _), PropElem)

% Spill-through abutment — no retainment element
\+ member(elem(retainment, _, _, _, _, _, _), PropElem)

% Pile foundation used
member(elem(piles, _, _, _, _, _, _), PropElem)
```

---

## Abutment Style — `abutment_style/3`

```prolog
abutment_style(+PropElem, -Style, -WallType)
%   Style    = earth_retaining | spill_through
%   WallType = concrete_gravity | mse_wall | timber_crib | gabion_block | none
```

---

## Cost Model

`price_solution(+Sol, -PricedItems, -TotalCost)` returns one `priced/3` item per line:

| Item | Formula |
|---|---|
| Girders | `CostPerM × TotalSpanLength × NGirders` |
| Concrete gravity wall (B ≤ 2.5 m) | `2 × H × B × W × 1700 $/m³` |
| Concrete gravity wall (B > 2.5 m) | `2 × (1.5×B + (H−1.5)×1.5) × W × 1700` (T-section) |
| MSE / gabion wall | `2 × H × W × Rate $/m²` |
| Stub abutment | `2 × H × B × W × 1700 $/m³` |
| Embankment | `2 × 30 × W × H` (flat rate) |
| Piles | `2 × NPiles × 6000 $` (both abutments) |
| Piers | `NPiers × 20000 × W` |

W = roadway width (m), H = wall height (m), B = base width (m).

`solution_cost(+Sol, -TotalCost)` is a convenience wrapper.

---

## Configuring for a New Site

Edit **`site_facts`** only:

1. Replace `soil_log1/3` facts with borehole data (Type, Density, Elevation)
2. Set `bottom/1` — lowest obstacle or scour elevation
3. Set `approach_elevation/1` and `design_high_water_level/1`
4. Set `hydraulic_opening/1` — natural channel width at bottom elevation
5. Set `roadway_width/1` and `bearing_x_load/1`
6. Adjust `frost_depth/1` for the region
7. Adjust `pile_pmax/1`, `pile_hlat/1` for the chosen pile product

Edit **`bridge_facts`** to update price lists or add girder/pile products.

**Soil type atoms**: `gravel`, `sand`, `silt`, `clay`, `rock`  
**Density atoms**: `loose`, `medium`, `dense`, `soft`, `firm`, `stiff`, `sound`, `hard`

---

## Common Queries

```prolog
% All solutions
?- solve_all(Sols), print_all_solutions(Sols).

% 5 cheapest
?- solve_all(Sols),
   maplist([S,C-S]>>(solution_cost(S,C)), Sols, Pairs),
   msort(Pairs, Sorted),
   length(Top5, 5), append(Top5, _, Sorted),
   pairs_values(Top5, Best),
   print_all_solutions(Best).

% Cheapest concrete gravity wall, 1 span
?- solve_all(Sols),
   include([S]>>(S=solution(1,PE,_,_,_,_),
                 member(elem(retainment,_,_,_,_,_,concrete_gravity),PE)),
           Sols, Filt),
   maplist([S,C-S]>>(solution_cost(S,C)), Filt, Pairs),
   msort(Pairs, [_-Best|_]),
   print_solution(Best).

% Spill-through only
?- solve_all(Sols),
   include([S]>>(S=solution(_,PE,_,_,_,_),
                 \+ member(elem(retainment,_,_,_,_,_,_),PE)),
           Sols, Filt),
   print_all_solutions(Filt).
```
