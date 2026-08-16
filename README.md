# Bridge Abutment Configuration & Cost Optimizer

A SWI-Prolog model that enumerates and prices every structurally valid
abutment/bridge configuration for a given site — embankment vs. retaining wall
(concrete gravity, MSE, timber crib, gabion, sheet piling), spill-through vs.
pile foundation, scour protection, girder type and span layout, interior piers —
and reports them sorted by cost, so the cheapest design (overall or within a
category) can be identified quickly for a given soil profile and site geometry.

It is a design-space search, not a single calculation: for one soil log it can
produce dozens of valid, fully-costed configurations by backtracking over wall
type, footing-vs-pile, scour mitigation method, and girder type.

## Requirements

[SWI-Prolog](https://www.swi-prolog.org/) (tested with the standard Windows
build). No other dependencies.

## Quick Start

```prolog
?- consult('prolog_bridge_config.pl').

% Every valid configuration for the current site_facts.pl
?- solve_all(Solutions), print_all_solutions(Solutions).

% Cheapest overall
?- solve_all(Sols),
   maplist([S,C-S]>>(solution_cost(S,C)), Sols, Pairs),
   msort(Pairs, [_-Best|_]),
   print_solution(Best).
```

`run_solve.pl` is a ready-to-run script that consults the system, solves, and
prints the cheapest overall solution plus a few filtered categories
(full-height concrete wall, spill-through, 2-span spill-through):

```
swipl run_solve.pl
```

## What It Models

For a site defined by borehole logs, elevations, and hydraulic constraints, the
model:
1. Samples the soil profile and classifies each layer as sloped fill, a
   confined (walled) face, or rock.
2. Sizes whichever retaining walls that geometry requires — gravity-wall
   stability (Coulomb earth pressure, overturning/sliding, settlement, bearing
   capacity), a driven-pile fallback foundation, or a sheet-pile embedment
   design, plus frost protection and river scour mitigation.
3. Derives the resulting bridge length and selects a girder type (precast
   voided slab, precast NEXT beam, or custom steel beam) and span layout that
   covers it.
4. Sizes interior piers, if any.
5. Prices every element and sums to a total cost per configuration.

## Project Layout

| File | Role |
|---|---|
| `site_facts.pl` | **Edit per project.** Soil log, elevations, hydraulic data, roadway width, wall-type/scour/sheet-pile rules, pile parameters |
| `Abut_config_facts.pl` | Shared soil property tables (friction angle, elastic modulus) |
| `bridge_facts.pl` | Girder/pile catalogue: stock lengths, section properties, self-weight |
| `price_list.pl` | Unit rates and pricing predicates |
| `dead_load.pl` | Simply-supported dead-load reactions at abutments/piers |
| `Live_load.pl` | CHBDC truck live-load model |
| `abut_soil_config_8.pl` | Core geometry engine: soil sampling, layer classification, element compilation, embedment/scour helpers |
| `abut_tree_gravity.pl` | Gravity-wall stability design |
| `Abut_tree_footing_def.pl` | Elastic strip-footing settlement (CFEM 4th s.11.3.4) |
| `CFEM_4th_prolog_qu.pl` | Ultimate bearing capacity (CFEM 4th s.10.2, Vesic factors) |
| `abut_pile_fallback.pl` | Pile foundation search |
| `abut_print.pl` | Output/reporting only |
| `prolog_bridge_config.pl` | Top-level solver (`solve_all/1`), span/pier config, solution classification |
| `run_solve.pl` | Example entry-point script |
| `full_height_vs_spill_study.pl`, `spill_study_temp.pl` | Parametric studies across site height, soil density, and rock depth |

Consult chain: `prolog_bridge_config.pl` → `abut_soil_config_8.pl` (→
`site_facts.pl`, `Abut_config_facts.pl`, `abut_pile_fallback.pl` → the three
design modules, `abut_print.pl`) → `bridge_facts.pl` → `dead_load.pl` →
`Live_load.pl` → `price_list.pl`.

## Configuring for a New Site

At minimum, edit `site_facts.pl`: soil log, `bottom`, `approach_elevation`,
`design_high_water_level`, `hydraulic_opening`, `roadway_width`. See
`rag_system_guide.md`'s "Configuring for a New Site" section for the full
checklist, including two easy-to-miss items — `Live_load.pl` has its own
`deck_width` fact that must be kept in sync with `roadway_width` manually, and
the retained-soil unit weight actually used in wall design lives in
`abut_tree_gravity.pl`, not `site_facts.pl`.

## Documentation

- **`rag_system_guide.md`** — the algorithm: how the solver searches (every
  branch/choice point it backtracks over), the data structures, and a
  step-by-step procedure precise enough to reproduce a solution by hand.
- **`rag_engineering_reference.md`** — the formulas: every calculation, design
  standard, and constant used, plus notes on non-obvious current behavior
  (simplifications, unused facts, checks that are computed but not enforced).

Both were written to be self-contained enough to hand to an LLM (or a new
engineer) without Prolog access and still get correct, traceable results —
verified by hand-deriving a full solution from the docs alone and matching the
solver's actual output to the dollar.

## Known Limitations

Single-borehole (no transverse soil variation), symmetric bridge (both
abutments identical), no seismic loading, static pile design only, sheet-pile
sizing is preliminary rule-of-thumb only. Full list, with rationale, in
`rag_engineering_reference.md`.
