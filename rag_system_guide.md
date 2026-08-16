# Bridge Configuration System — Manual Solver Guide

## Purpose

This SWI-Prolog system enumerates and costs every valid bridge/abutment
configuration for a site: for each span count, it backtracks over embankment
geometry, retaining-wall type, footing-vs-pile foundation, scour mitigation, and
girder type, producing a full set of costed `solution/6` terms, sortable to find
the cheapest overall or the cheapest within a category (e.g. "cheapest
spill-through" or "cheapest full-height concrete wall").

**This document's job is different from a typical code walkthrough: it is a
procedure precise enough to execute by hand (or as an LLM, "in your head") without
running Prolog at all**, so that given a site's facts you can reproduce the same
set of solutions — and the same costs — that `solve_all/1` would produce. Every
formula referenced below is fully specified in the companion document,
`rag_engineering_reference.md`; this document is about **sequencing and search**:
what gets computed when, and — critically — exactly where the algorithm branches
into multiple candidate solutions versus where it commits to a single answer.

If you *do* have access to a Prolog interpreter, the reference implementation is
still authoritative — use it to check your manual work. A short appendix of
Prolog queries is included at the end for that purpose.

---

## Data Structures

### Element — `elem/7`
```prolog
elem(Type, BotX, BotElev, TopX, TopElev, B, WallType)
```
| Arg | Meaning |
|---|---|
| `Type` | `embankment`, `retainment`, `rock_face`, `stub_abutment`, `bearing_x`, `sheet_piling`, `rip_rap`, `piles` |
| `BotX` | X at bottom of element (m; 0 = bridge centreline, negative = embankment side) |
| `BotElev` | Elevation at bottom (m) |
| `TopX` | X at top (back face, for walls) |
| `TopElev` | Elevation at top (m) |
| `B` | Base width (m) for walls/stub; extent (m) for `rip_rap`; 0 for `sheet_piling`/`rock_face`/`bearing_x` |
| `WallType` | `concrete_gravity`, `mse_wall`, `timber_crib`, `gabion_block`, `sheet_piling`, or `none` |

**Pile element** uses the slots differently:
```prolog
elem(piles, RowCounts, Spacings, PileLength, none, none, none)
%   RowCounts  = [N1] | [N1,N2] | [N1,N2,N3]        -- piles per row
%   Spacings   = [X1] | [X1,X2] | [X1,X2,X3]        -- row X positions from cap front (m)
%   PileLength = depth to rock at the cap elevation (m); rock-socketed if < 5 m
```

### Solution — `solution/6`
```prolog
solution(NSpans, PropElem, BridgeLength, GirderType, SpanLengths, Piers)
```
| Arg | Meaning |
|---|---|
| `NSpans` | 1, 2, or 3 |
| `PropElem` | list of `elem/7` (both abutments; symmetric, priced ×2) |
| `BridgeLength` | total bridge length (m), from designed geometry |
| `GirderType` | `voided_precast`, `next_beams`, or `steel_beams` |
| `SpanLengths` | list of span lengths (m) |
| `Piers` | `piers(NPiers, Type, Height, BotElev, BearingElev)` |

### Priced item — `priced/3`
```prolog
priced(Elem, Label, Cost)   % Cost already doubled for both abutments where applicable
```

---

## Geometry Conventions

- X = 0 at the bridge centreline; X is **negative** toward the embankment/approach
  side, more negative farther from the river.
- `BotX` of a wall = toe (river-facing face, at base elevation).
- `TopX` of a wall = back face (embankment-facing face, at base elevation).
  - Gravity walls without a fixed back offset: `TopX = BotX − B`.
  - `mse_wall`, `sheet_piling`: fixed setback, `TopX = BotX − 1.5`, independent of `B`.
- Stub abutment is centred on its bearing X: `BotX = BearingX + B/2`, `TopX = BearingX − B/2`.
- The `bearing_x` element (when a wall itself reaches the surface, no stub above
  it) marks the girder bearing seat position, used for bridge-length calculation.
- Processing direction for element design is always **bottom to top**: the X
  coordinate at the top of one element becomes the starting X for the element
  above it.

---

## High-Level Flow

```
solve_all(Solutions):
    Solutions = every solve_one(Sol) found by exhaustive backtracking

solve_one(Sol), for one branch of the search:
    1.  pick N (span count)               -- CHOICE: N ∈ {1, 2, 3}
    2.  reset dynamic state; load soil log; compute preliminary bearing_x_load
    3.  compute bearing elevation, surface elevation, depth-from-ratio for this N
    4.  sample soil every 1.5 m; build sorted layer list above site bottom
    5.  classify layers bottom-to-top (slope/confined/vertical)   -- CHOICE POINTS (see below)
    6.  compile classified layers into elem/7 stubs (embankment / retainment / rock_face / stub_abutment)
    7.  design each element bottom-to-top:
          - embankment: 2H:1V slope geometry (no choice)
          - retaining wall: wall type, footing-vs-pile, scour mitigation  -- CHOICE POINTS
          - stub abutment: footing-vs-pile (or pile-only if pure spill-through at a river) -- CHOICE POINTS
    8.  compute final bridge length from the designed geometry
    9.  pick girder type + span lengths covering the bridge length  -- CHOICE: up to 3, one per girder type
    10. size interior piers (deterministic, given NPiers from step 9)
    Sol = solution(N, PropElem, BridgeLength, GirderType, SpanLengths, Piers)
```

Every solution in the final set is one complete path through all the choice
points below. To manually reproduce `solve_all`, enumerate the choice points as
nested loops (outer = step 1, innermost = step 9) and, for each combination,
run the deterministic steps in between.

---

## Choice Points (the actual search tree)

This is the part that matters most for faithfully reproducing results — everything
else in the algorithm is a deterministic calculation. There are exactly five kinds
of branching:

1. **Span count**: `N ∈ {1, 2, 3}` — always all three are tried.

2. **Gravel layer geometry** (`slope` vs `confined`), one decision per gravel
   layer in the profile, constrained by the rules in the engineering reference's
   "Embankment / Wall Layer Classification" section. Rock layers have no choice
   (always `vertical`). This is what produces multiple distinct embankment/wall
   *shapes* for the same soil log and span count.

3. **Retaining wall type**, once per `retainment` element in the (now fixed)
   geometry: either the 2 types in `wall_type_at_surface` (if this wall reaches
   the true road surface) or the 5 types in `retaining_wall_type` (otherwise).
   Each wall type that produces *any* valid design (footing or pile, see next
   point) becomes a separate candidate solution.

4. **Footing vs. pile foundation**, once per gravity-type wall (`concrete_gravity`,
   `mse_wall`, `timber_crib`, `gabion_block` — not `sheet_piling`, which has its
   own non-footing design) and once for the stub abutment:
   - The **footing** design (base-width search) is attempted; if it finds *any*
     passing width, that is offered as one candidate — the search does not
     explore multiple footing widths per wall, only the first (narrowest, since
     `B` increases monotonically) that passes every check.
   - **Only for `concrete_gravity`** (wall or stub), a **pile** foundation is
     *also* offered as a separate candidate, independent of whether the footing
     succeeded — a footing that technically passes can still be pricier than
     piles, and this model doesn't know cost at design time, so both are kept
     and the cost sort decides later. Every other wall type has no pile
     alternative: if its footing fails, that wall type simply produces no
     solution and the search moves to the next wall type.
   - **Exception**: a stub abutment that sits directly on embankment slope with
     *no* retaining wall below it at all (a true spill-through), at a river
     crossing, skips the footing attempt entirely and goes straight to piles
     (piles are required in this specific case, not merely offered as one option).

5. **Scour mitigation method**, once per gravity wall whose base sits at or below
   the riverbed at a river crossing (and not founded on rock): `extend` and/or
   `sheet_pile`, whichever `wall_scour_mitigation/2` permits for that wall type —
   see the reference for which types get which options. Each permitted method
   that succeeds is a separate candidate. `sheet_piling`-as-scour-protection can
   fail outright (rock blocks the embedment) without eliminating the `extend`
   alternative, and vice versa.

6. **Girder type**, once per finished abutment geometry: each of `voided_precast`,
   `next_beams`, `steel_beams` that has *any* stock length satisfying the
   tight-fit span rule contributes one candidate (the shortest qualifying stock
   length for that type — not every stock length that would fit).

**What does *not* branch:** the base-width search within a single footing or pile
attempt (first pass wins), and multi-span-length combinations for the same girder
type (only the shortest fitting combination is tried, via a committed search).

The enumeration *order* Prolog would explore these in doesn't affect the final
cost-sorted results — `solve_all` collects everything before anything is ranked.
Order only matters if you're intentionally reproducing a "first solution found"
style query; for "cheapest overall" or "cheapest in category X," collect the full
set first.

---

## Step-by-Step Procedure

### 1–3. Setup for one N
```
BridgeLength0   = initial estimate (see reference: "Initial Bridge Length Estimate")
DepthFromRatio  = max(BridgeLength0 / (N × 30), 1.5)
BearingElev     = max(DHWL + 0.3, ApproachElev − DepthFromRatio)
SurfaceElev     = BearingElev + DepthFromRatio
bearing_x_load  = preliminary estimate from dead load (at SpanEstimate = BridgeLength0/N)
                  and live load (CHBDC truck model) — see reference "Loads" section.
                  This value is frozen for the rest of this N-branch.
```

### 4. Soil Model
- Copy every `soil_log1` fact to the working `soil_log` set.
- Add one synthetic entry: `(gravel, dense, SurfaceElev)`.
- Sample every 1.5 m from the highest logged elevation down to the lowest,
  assigning each sample the type/density of the log entry whose elevation is the
  nearest one at-or-above it (see reference for the exact stratum-lookup rule).
- Discard samples at or below the site `bottom` elevation.
- Sort the remaining samples by elevation, ascending (bottom to top) — this is
  the working `LayerList` for geometry classification.

### 5. Layer Classification
Process `LayerList` bottom to top. Start with the site `bottom` elevation as the
first profile node (tagged `bottom`), then for each soil sample:
- If `rock`: tag `vertical`.
- If `gravel`: apply the slope/confined rule table (reference doc), tracking the
  `Pcon`/`Pslp` flags across the whole climb. This is choice point #2 above —
  branch the search wherever the rule table offers `slope ; confined`.

After the last sample, prepend a final node `(SurfaceElev, surface)`. The result
is `Profile`, a bottom-to-top list of `[Elevation, Tag]` pairs (`bottom`, then
zero or more `slope`/`confined`/`vertical`, then `surface`).

### 6. Element Compilation
Look at the top two entries of `Profile` (just below `surface`) to decide the
stub-abutment offset (reference doc, "Bearing Point Placement"): `3.0`, `1.5`, or
`none`. If not `none`, create a `stub_abutment` stub whose `BotElev` is
`BearingElev − frost_depth/cos(atan 0.5)` (i.e. the stub's own frost-protected
base, on the same 2:1 diagonal used for gravity-wall frost adjustment above the
riverbed) and whose `TopElev` is `BearingElev`.

Then walk the remaining `Profile` entries bottom to top, merging **consecutive
entries of the same structural type** (via the `slope→embankment`,
`confined→retainment`, `vertical→rock_face` mapping) into a single `elem/7` stub
spanning from the lowest such entry's elevation to the highest. X and B fields
stay uninstantiated at this stage — they're filled in during design (step 7).

### 7. Element Design (bottom to top, `CurrX` starts at 0)

**`rock_face`**: vertical, `BotX = TopX = CurrX` (unchanged), `B = 0`.

**`embankment`**: 2H:1V slope.
```
Height = TopElev − BotElev
TopX   = CurrX − 2 × Height
B      = 2 × Height
```
`CurrX` for the next element above becomes this `TopX`.

**`retainment`** (choice points #3, #4, #5 all live here):
1. Determine `Above` (embankment if the element above is embankment, else none)
   and `Below` (the structural type of whatever was designed just before this,
   or `bottom` if nothing yet).
2. Determine whether this wall's `TopElev` equals the true `SurfaceElev` — if so,
   it carries `bearing_x_load` and is restricted to `wall_type_at_surface` types;
   otherwise `BearingLoad = 0` and all 5 `retaining_wall_type` types are tried.
3. For each candidate `WallType`:
   - **If `sheet_piling`**: compute embedment depth via the D/H-ratio method
     (reference doc). If it fails (rock blocks it), no candidate for this type.
     If it succeeds, optionally add a `rip_rap` element (sheet piling is its own
     scour protection at a river crossing) — no footing/pile design at all.
   - **Else (gravity wall)**: apply frost-depth adjustment (with rock-refusal
     capping), then scour mitigation if applicable (choice point #5, at a river
     crossing with base at/below riverbed and not on rock), then run
     footing-vs-pile design (choice point #4) using `BearingLoad`, `Above`,
     `Below`, and this wall type's allowable settlement.
4. Whichever candidate(s) succeed, each becomes a separate `Processed` element
   (plus any pile/scour side-elements) in the geometry, and `ProcTopX` (that
   candidate's back-face X) becomes `CurrX` for the element above **in that
   candidate's own branch** — different wall-type candidates diverge from here
   on, each building its own version of everything above.
5. If this wall's `TopElev` equals `SurfaceElev`, also append a `bearing_x`
   marker element (`BotX = ProcBotX − 0.6`, spanning `SurfaceElev − DepthFromRatio`
   to `SurfaceElev`) for the bridge-length calculation.

**`stub_abutment`**: `BearingX = CurrX + Offset` (the offset from step 6).
- If this is the pure-spill-through-at-a-river special case (no retainment
  element anywhere below in this branch, and `obstacle_type = river`): pile
  foundation only (no footing attempt), plus a `rip_rap` element at the stub base.
- Otherwise: footing-vs-pile (choice point #4), always as `concrete_gravity`,
  `BearingLoad = bearing_x_load`, no scour element.
- Either way, once `B` (or the pile cap width) is known:
  `BotX = BearingX + B/2`, `TopX = BearingX − B/2`.

### 8. Bridge Length
```
XBearing = |BotX of the bearing_x element|                    (if a wall reaches the surface)
         = |(RightX + LeftX)/2 of the stub_abutment element|   (if a stub is present)
BridgeLength = hydraulic_opening + 2 × XBearing
```

### 9. Span Configuration
For each girder type, in the order `voided_precast`, `next_beams`, `steel_beams`:
find the shortest catalogue length (per the tight-fit rule in the reference doc)
that covers `BridgeLength` for this `N`. If none exists for a given type, that
type contributes no candidate for this branch. Each type that succeeds is a
separate candidate solution (choice point #6).

### 10. Piers
```
NPiers = N − 1     (0, 1, or 2)
Height = BearingElev − BottomElev   (0 if NPiers = 0)
```
Always `pipe_pile_bent`, no further design.

### Assembling and Costing
Each complete `(N, PropElem, BridgeLength, GirderType, SpanLengths, Piers)` tuple
is one member of `Solutions`. Price each with the formulas in the "Cost Model"
section of the reference doc: one line item per element in `PropElem`, one for
the girders (two line items for `steel_beams`: steel + deck concrete), one for
piers; sum for the total. Sort by total to answer "cheapest" questions; filter
`PropElem`/`GirderType`/`NSpans` first to answer category questions (see next
section).

---

## Classifying a Solution

```
abutment_style(PropElem) =
    earth_retaining(WallType)   if PropElem contains a `retainment` element (WallType = its wall type)
    spill_through(none)         otherwise

scour_label(PropElem) =
    'scour: sheet piling + rip rap'     if a sheet_piling element is present
    'scour: extended wall + rip rap'    if a rip_rap element AND a retainment element are present
    'scour: rip rap on embankment'      if a rip_rap element is present, no retainment element
    ''                                   otherwise

pile_foundation_used(PropElem) = PropElem contains a `piles` element
```

> **Code behavior — `abutment_style/3` only classifies correctly in "generate"
> mode.** Its Prolog clauses are:
> ```prolog
> abutment_style(PropElem, earth_retaining, Type) :-
>     member(elem(retainment, _, _, _, _, _, Type), PropElem), !.
> abutment_style(_, spill_through, none).
> ```
> Called the natural way, with `Style`/`WallType` left unbound so Prolog computes
> them (`abutment_style(PropElem, Style, WallType)`), this works as described
> above. But if you call it to **test** a specific category by pre-binding the
> style — e.g. `abutment_style(PropElem, spill_through, _)` to filter for
> spill-through solutions — the first clause's head fails to unify (its second
> argument is fixed to `earth_retaining`, not `spill_through`) and Prolog falls
> straight through to the unconditional second clause, which matches **any**
> `PropElem` at all. Such a filter silently accepts every solution, retaining
> or not. Always generate first, then compare: `abutment_style(P, St, _), St ==
> spill_through` — that's the pattern this project's own scripts use
> (`prolog_bridge_config.pl`'s callers, `full_height_vs_spill_study.pl`).

Useful category filters seen in this project's parametric studies (see
`full_height_vs_spill_study.pl` for the reference implementation):

- **Full-height concrete wall (base to true surface)**: `earth_retaining` with
  `WallType = concrete_gravity`, and PropElem has **no** `embankment` element and
  **no** `stub_abutment` element (the wall itself is the whole abutment, base to
  road surface — no fill above it, no separate stub on top).
- **Full height to bearing (any wall type)**: PropElem has both a `retainment`
  element and a `stub_abutment` element, and any `embankment` element between
  them is ≤ 1.5 m tall (the smallest embankment height this model can produce,
  since soil is sampled every 1.5 m) — i.e. the wall carries essentially the
  whole retained height, with only a token fill zone above it.
- **Spill-through**: `abutment_style` is `spill_through` (no wall at all).

---

## Configuring for a New Site

Edit **`site_facts.pl`**:
1. Replace `soil_log1/3` facts with borehole data (Type, Density, Elevation).
2. Set `bottom/1` — lowest obstacle or scour reference elevation.
3. Set `approach_elevation/1` and `design_high_water_level/1`.
4. Set `hydraulic_opening/1` — natural channel width at bottom elevation.
5. Set `roadway_width/1` and (see step 7) `deck_width/1` to match.
6. Adjust `frost_depth/1` for the region.
7. **Also update `deck_width/1` in `Live_load.pl`** to match `roadway_width` —
   these are separate facts, not synced automatically (see reference doc note).
8. Adjust `pile_pmax/1`, `pile_hlat/1` for the chosen pile product.
9. Set `obstacle_type/1` (`river`/other) and, if `river`, check `scour_depth/1`,
   `sheet_pile_depth/1`, `rip_rap_extent/1`.
10. If the retained-soil unit weight needs to change from 18 kN/m³, **edit
    `soil_gamma/1` in `abut_tree_gravity.pl`**, not `site_facts.pl` — the copy in
    `site_facts.pl` is never actually used (module-shadowing; see reference doc).

Edit **`bridge_facts.pl`** / **`price_list.pl`** to update the girder/pile
catalogue or unit prices.

---

## File Map (for provenance / reference only)

| File | Role |
|---|---|
| `site_facts.pl` | Per-project facts: soil log, elevations, hydraulic data, roadway width, wall-type/scour/sheet-pile rules, pile parameters |
| `Abut_config_facts.pl` | Shared soil property tables: `friction_angle/3`, `elastic_modulus/3`, `elem_type/2` |
| `bridge_facts.pl` | Girder/pile catalogue: stock lengths, section properties, self-weight |
| `price_list.pl` | All unit rates and the pricing predicates (`price_solution/3`, etc.) |
| `dead_load.pl` | Simply-supported dead-load reactions at abutments/piers |
| `Live_load.pl` | CHBDC truck live-load model (axle groups, DLA, lane factors) |
| `abut_soil_config_8.pl` | Core geometry engine: soil sampling, layer classification, element compilation, embedment/scour helpers |
| `abut_tree_gravity.pl` (module) | Gravity-wall stability design: Coulomb Ka, equilibrium, FS checks, eccentricity |
| `Abut_tree_footing_def.pl` (module) | Elastic strip-footing settlement (CFEM 4th s.11.3.4) |
| `CFEM_4th_prolog_qu.pl` (module) | Ultimate bearing capacity (CFEM 4th s.10.2, Vesic factors) |
| `abut_pile_fallback.pl` | Pile foundation search; wraps footing-vs-pile choice |
| `abut_print.pl` | Output/reporting predicates only — no design logic |
| `prolog_bridge_config.pl` | Top-level solver: `solve_all/1`, span config, pier config, `abutment_style/3`, `scour_label/2` |

**Consult chain** (load order): `prolog_bridge_config.pl` → `abut_soil_config_8.pl`
(→ `site_facts.pl`, `Abut_config_facts.pl`, `abut_pile_fallback.pl` → the three
modules, `abut_print.pl`) → `bridge_facts.pl` → `dead_load.pl` → `Live_load.pl` →
`price_list.pl`.

---

## Appendix: Reference Prolog Queries

If a Prolog interpreter is available, load the system with:
```prolog
?- consult('prolog_bridge_config.pl').
```

```prolog
% All solutions
?- solve_all(Sols), print_all_solutions(Sols).

% Cheapest overall
?- solve_all(Sols),
   maplist([S,C-S]>>(solution_cost(S,C)), Sols, Pairs),
   msort(Pairs, [_-Best|_]),
   print_solution(Best).

% Cheapest spill-through only
?- solve_all(Sols),
   include([S]>>(S=solution(_,PE,_,_,_,_), \+ member(elem(retainment,_,_,_,_,_,_),PE)), Sols, Filt),
   maplist([S,C-S]>>(solution_cost(S,C)), Filt, Pairs),
   msort(Pairs, [_-Best|_]),
   print_solution(Best).

% Cheapest concrete-gravity wall, 1 span
?- solve_all(Sols),
   include([S]>>(S=solution(1,PE,_,_,_,_),
                 member(elem(retainment,_,_,_,_,_,concrete_gravity),PE)), Sols, Filt),
   maplist([S,C-S]>>(solution_cost(S,C)), Filt, Pairs),
   msort(Pairs, [_-Best|_]),
   print_solution(Best).
```

`full_height_vs_spill_study.pl` and `spill_study_temp.pl` contain worked examples
of parametric studies across site-bottom height, soil density, and rock depth,
including the category predicates described above (`is_full_height_to_surface/1`,
`is_full_height_to_bearing/1`, etc.) — useful as a second reference implementation
of the classification logic in this guide.
