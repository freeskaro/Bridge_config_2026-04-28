% full_height_vs_spill_study.pl
%
% Parametric study comparing three specific abutment regimes:
%
%   1. is_full_height_to_bearing/1  -- "full height retaining wall
%      (river bed to bearing support)": the retaining wall spans
%      continuously from the river bed up to the bearing elevation, with
%      NO embankment fill element between the wall and the stub/bearing
%      seat. Any wall type (concrete_gravity, mse_wall, gabion_block,
%      sheet_piling, timber_crib) qualifies.
%
%   2. is_full_height_to_surface/1  -- "full height concrete retaining
%      wall (frost depth to road surface)": a concrete_gravity wall
%      reaching the actual road surface directly -- no embankment AND no
%      separate stub_abutment above it (the wall itself IS the abutment,
%      base to surface). Same definition used earlier in this project's
%      cost-estimate discussions.
%
%   3. spill_through -- abutment_style/3 == spill_through (no retaining
%      wall at all).
%
% Study grid: H (site bottom = approach_elevation - H) in {5,7,9} m,
% rock elevation 0-10 m below the river bed, soil uniformly loose or
% dense above the rock. Single span only (nspan fixed to 1), matching
% the convention used in spill_study_temp.pl for this project's earlier
% parametric studies.
%
% Usage:
%   ?- consult('full_height_vs_spill_study').
%   ?- run_full_height_study.   % 3-way WINNER summary (retaining_structure/surface_wall/spill)
%   ?- run_table.               % 4-column table: cheapest overall (+ its type), spill,
%                                % MSE-specific near-full-height, full-depth concrete
%                                % (pipe-delimited "ROW|..." lines)
%   ?- run_summary_table.       % same 4-column data, rendered as a readable markdown table
%                                % with comma-formatted costs and human-readable type labels

:- consult('prolog_bridge_config.pl').
:- dynamic(bottom/1).
:- dynamic(hydraulic_opening/1).
:- dynamic(soil_log1/3).
:- dynamic(nspan/1).
:- dynamic(allowable_settlement_for_wall/2).

setup_nspan1 :-
    retractall(nspan(_)),
    assertz(nspan(1)).

setup_mse25 :-
    retractall(allowable_settlement_for_wall(mse_wall,_)),
    assertz(allowable_settlement_for_wall(mse_wall,25)).

% ============================================================
% Category predicates
% ============================================================

% is_full_height_to_surface(+PropElem)
% Concrete gravity wall, base to road surface: no embankment, no stub.
is_full_height_to_surface(P) :-
    abutment_style(P, earth_retaining, concrete_gravity),
    \+ member(elem(embankment,_,_,_,_,_,_), P),
    \+ member(elem(stub_abutment,_,_,_,_,_,_), P).

% near_full_height_embankment_threshold(-Metres)
% A strictly zero-embankment "wall reaches the bearing point directly"
% design is unreachable in this model: compile_elements/3 only creates a
% stub_abutment when the top-most soil layer is classified "slope", and
% that same layer always becomes an actual embankment element -- checked
% empirically, the smallest embankment height ever produced is 1.5 m (the
% soil-sampling interval used by assert_soil_from_logs/0). So "full height
% to bearing" is redefined here as "as close to the bearing as this model
% can get": embankment height at or below that observed floor.
near_full_height_embankment_threshold(1.5).

% is_full_height_to_bearing(+PropElem)
% Any wall type, river bed to (near) bearing: a retainment element is
% present, a stub_abutment IS present (the bearing seat sits on top), and
% any embankment element between them is no taller than the practical
% minimum this model can produce (see near_full_height_embankment_threshold/1)
% -- i.e. the wall carries essentially the whole height, not just part of
% it with a substantial fill zone above.
is_full_height_to_bearing(P) :-
    member(elem(retainment,_,_,_,_,_,_), P),
    member(elem(stub_abutment,_,_,_,_,_,_), P),
    near_full_height_embankment_threshold(Thresh),
    ( member(elem(embankment,_,EBot,_,ETop,_,_), P) -> EmbH is ETop - EBot ; EmbH = 0 ),
    EmbH =< Thresh.

% ============================================================
% Per-combination solve + categorize
% ============================================================

% run_combo(+H, +Density, +RockDBelow, +HO)
run_combo(H, Density, RockDBelow, HO) :-
    ApproachElev = 100,
    Bottom is ApproachElev - H,
    RockElev is Bottom - RockDBelow,
    retractall(bottom(_)), assertz(bottom(Bottom)),
    retractall(hydraulic_opening(_)), assertz(hydraulic_opening(HO)),
    retractall(soil_log1(_,_,_)),
    assertz(soil_log1(gravel, Density, ApproachElev)),
    assertz(soil_log1(rock, sound, RockElev)),
    ( catch(solve_all(Solutions), _, Solutions=[]) -> true ; Solutions = [] ),
    ( Solutions == [] ->
        format("H=~w soil=~w rockD=~w HO=~w | NO SOLUTIONS~n",[H,Density,RockDBelow,HO])
    ;
        findall(Cost-Sol, (member(Sol,Solutions), price_solution(Sol,_,Cost)), AllPairs),
        keysort(AllPairs, AllSorted),

        ( findall(C-S, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), is_full_height_to_bearing(P)), BearList),
          BearList=[BC-BearSol|_] -> BearSol=solution(_,BearP,_,_,_,_), abutment_style(BearP,_,BearWT) ; BC=none, BearWT=none ),
        ( findall(C-S, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), is_full_height_to_surface(P)), SurfList),
          SurfList=[FC-_|_] -> true ; FC=none ),
        ( findall(C-S, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), abutment_style(P,St,_), St==spill_through), SpillList),
          SpillList=[SC-_|_] -> true ; SC=none ),

        winner_label3(BC, FC, SC, Winner),
        format("H=~w soil=~w rockD=~w HO=~w | retaining_structure=~w(~w) surface_wall=~w spill=~w | WINNER=~w~n",
               [H,Density,RockDBelow,HO,BC,BearWT,FC,SC,Winner])
    ).

% winner_label3(+BearingWallCost, +SurfaceWallCost, +SpillCost, -Label)
winner_label3(BC, FC, SC, Winner) :-
    findall(C-Cat, ( member(C-Cat, [BC-retaining_structure, FC-surface_wall, SC-spill]), number(C) ), Pairs),
    ( Pairs == [] -> Winner = none
    ; keysort(Pairs, [_-Winner|_])
    ).

% ============================================================
% Study driver (3-way WINNER summary)
% ============================================================

run_full_height_study :-
    setup_nspan1,
    setup_mse25,
    forall(member(H,[5,7,9]),
      forall(member(Density,[loose,dense]),
        forall(member(RockD,[0,4,8]),
          run_combo(H, Density, RockD, 15)))).

% ============================================================
% 4-column table: cheapest overall (+ its abutment type), spill-through,
% MSE wall (near-full-height-to-bearing specifically), full-depth concrete
% ============================================================

% is_mse_near_full_height(+PropElem)
% Same near-full-height-to-bearing test as is_full_height_to_bearing/1,
% narrowed to solutions whose wall type is specifically mse_wall -- used to
% report an MSE-specific cost column even when gabion_block or another
% type is cheaper overall in that category.
is_mse_near_full_height(P) :-
    is_full_height_to_bearing(P),
    abutment_style(P, _, mse_wall).

% combo4_data(+H, +Density, +RockDBelow, +HO,
%             -CheapestCost, -CheapType, -SpillCost, -MseCost, -FullCost)
% Solves one grid point and returns the raw values (no printing/formatting) --
% shared by run_table/0 (pipe-delimited) and run_summary_table/0 (markdown).
% Fails if the site produces no solutions at all.
combo4_data(H, Density, RockDBelow, HO, CheapestCost, CheapType, SpillCost, MseCost, FullCost) :-
    ApproachElev = 100,
    Bottom is ApproachElev - H,
    RockElev is Bottom - RockDBelow,
    retractall(bottom(_)), assertz(bottom(Bottom)),
    retractall(hydraulic_opening(_)), assertz(hydraulic_opening(HO)),
    retractall(soil_log1(_,_,_)),
    assertz(soil_log1(gravel, Density, ApproachElev)),
    assertz(soil_log1(rock, sound, RockElev)),
    ( catch(solve_all(Solutions), _, Solutions=[]) -> true ; Solutions = [] ),
    Solutions \== [],
    findall(Cost-Sol, (member(Sol,Solutions), price_solution(Sol,_,Cost)), AllPairs),
    keysort(AllPairs, AllSorted),
    AllSorted = [CheapestCost-CheapestSol|_],
    CheapestSol = solution(_,CheapP,_,_,_,_),
    abutment_style(CheapP, CheapSt, CheapWT),
    ( CheapSt == spill_through -> CheapType = spill_through ; CheapType = CheapWT ),

    ( findall(C, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), abutment_style(P,St,_), St==spill_through), SpillCosts),
      SpillCosts=[SpillCost|_] -> true ; SpillCost=none ),
    ( findall(C, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), is_mse_near_full_height(P)), MseCosts),
      MseCosts=[MseCost|_] -> true ; MseCost=none ),
    ( findall(C, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), is_full_height_to_surface(P)), FullCosts),
      FullCosts=[FullCost|_] -> true ; FullCost=none ).

% run_combo4(+H, +Density, +RockDBelow, +HO) -- pipe-delimited raw output (unchanged format)
run_combo4(H, Density, RockDBelow, HO) :-
    ( combo4_data(H, Density, RockDBelow, HO, CheapestCost, CheapType, SpillCost, MseCost, FullCost) ->
        format("ROW|~w|~w|~w|~0f|~w|~w|~w|~w~n",
               [H,Density,RockDBelow,CheapestCost,CheapType,SpillCost,MseCost,FullCost])
    ;
        format("H=~w~t~10|~w~t~20|rockD=~w~t~30|NO SOLUTIONS~n",[H,Density,RockDBelow])
    ).

run_table :-
    setup_nspan1,
    setup_mse25,
    forall(member(H,[5,7,9]),
      forall(member(Density,[loose,dense]),
        forall(member(RockD,[0,4,8]),
          run_combo4(H, Density, RockD, 15)))).

% ============================================================
% Pretty markdown summary table (matches the format used when reporting
% this study's results in chat / the paper: comma-separated costs, a
% human-readable wall-type label, "—" for categories with no solution)
% ============================================================

% money(+Number|none, -Atom) -- e.g. 1086640 -> '1,086,640'; none -> '—'
money(none, '—') :- !.
money(N, Atom) :-
    Rounded is round(N),
    number_codes(Rounded, Codes),
    reverse(Codes, RevCodes),
    money_group(RevCodes, 0, RevGrouped),
    reverse(RevGrouped, GroupedCodes),
    atom_codes(Atom, GroupedCodes).

money_group([], _, []).
money_group([C|Cs], N, [C|Rest]) :-
    N1 is N + 1,
    ( Cs \== [], N1 mod 3 =:= 0 -> Rest = [0',|Rest1] ; Rest = Rest1 ),
    money_group(Cs, N1, Rest1).

% type_label(+WallTypeOrNone, -Label) -- human-readable name for the table's Type column
type_label(none, '—').
type_label(spill_through, 'Spill-through').
type_label(gabion_block, 'Gabion').
type_label(mse_wall, 'MSE').
type_label(concrete_gravity, 'Concrete gravity').
type_label(sheet_piling, 'Sheet piling').
type_label(timber_crib, 'Timber crib').

soil_label(loose, 'Loose').
soil_label(dense, 'Dense').

print_summary_header :-
    format("| H | Soil | Rock D | Cheapest ($) | Type | Spill-Through ($) | MSE ($) | Full-Height Wall ($) |~n"),
    format("|---|------|--------|--------------|------|--------------------|---------|------------------------|~n").

print_summary_row(H, Density, RockD, CheapestCost, CheapType, SpillCost, MseCost, FullCost) :-
    soil_label(Density, SoilLbl),
    type_label(CheapType, TypeLbl),
    money(CheapestCost, CheapStr),
    money(SpillCost, SpillStr),
    money(MseCost, MseStr),
    money(FullCost, FullStr),
    format("| ~w | ~w | ~w | ~w | ~w | ~w | ~w | ~w |~n",
           [H, SoilLbl, RockD, CheapStr, TypeLbl, SpillStr, MseStr, FullStr]).

run_summary_table :-
    setup_nspan1,
    setup_mse25,
    print_summary_header,
    forall(member(H,[5,7,9]),
      forall(member(Density,[loose,dense]),
        forall(member(RockD,[0,4,8]),
          ( combo4_data(H, Density, RockD, 15, CheapestCost, CheapType, SpillCost, MseCost, FullCost) ->
              print_summary_row(H, Density, RockD, CheapestCost, CheapType, SpillCost, MseCost, FullCost)
          ;
              format("| ~w | ~w | ~w | NO SOLUTIONS | | | | |~n", [H, Density, RockD])
          )))).
