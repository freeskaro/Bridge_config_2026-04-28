% prolog_bridge_config
% Integrated bridge configuration module.
%
% Consults abut_soil_config_8 for abutment/soil geometry and bridge length,
% then selects superstructure spans and pier type.
%
% A solution comprises:
%   - One embankment configuration (PropElem from abutment geometry)
%   - Bridge length derived from the designed abutment geometry
%   - Girder type and span lengths covering that bridge length
%   - Piers: one per interior support
%
% Entry points:
%   solve_all(-Solutions)          % collect every valid solution into a list
%   print_all_solutions(+Solutions)

:- consult('abut_soil_config_8.pl').
:- consult('bridge_facts.pl').
:- consult('dead_load.pl').
:- consult('Live_load.pl').
:- consult('price_list.pl').



% ============================================================
% Bearing / Surface Setup for a Specific Span Count
% ============================================================

% compute_bearing_for_nspan(+N, +BridgeLength0,
%                           -BearingElev, -DepthFromRatio, -SurfaceElev)
compute_bearing_for_nspan(N, BridgeLength0, BearingElev, DepthFromRatio, SurfaceElev) :-
    design_high_water_level(DHWL),
    approach_elevation(ApproachElev),
    DepthFromRatio is max(BridgeLength0 / (N * 30), 1.5),
    RawElev        is ApproachElev - DepthFromRatio,
    BearingElev    is max(DHWL + 0.3, RawElev),
    SurfaceElev    is BearingElev + DepthFromRatio.

% ============================================================
% Span Configuration
% span_config(+NSpans, +BridgeLength, -GirderType, -SpanLengths, -NPiers)
% Spans must cover BridgeLength but not exceed it by 3 m (tight fit rule).
% ============================================================

span_config(1, BridgeLength, GirderType, [L], 0) :-
    girder_type(GirderType),
    once((girder_lengths(GirderType, L), L >= BridgeLength, L < BridgeLength + 3)).

span_config(2, BridgeLength, GirderType, [L, L], 1) :-
    girder_type(GirderType),
    once((girder_lengths(GirderType, L), 2*L >= BridgeLength, 2*L < BridgeLength + 3)).

% 3-span symmetric: L1, L2, L1
span_config(3, BridgeLength, GirderType, [L1, L2, L1], 2) :-
    girder_type(GirderType),
    once((girder_lengths(GirderType, L1), girder_lengths(GirderType, L2),
          L2 >= L1, 2*L1+L2 >= BridgeLength, 2*L1+L2 < BridgeLength + 3)).

sum_spans([], 0).
sum_spans([H | T], S) :- sum_spans(T, S1), S is S1 + H.

% ============================================================
% Abutment Style (derived from designed PropElem)
% ============================================================

% earth_retaining when any retainment element is present
abutment_style(PropElem, earth_retaining,Type) :-
    member(elem(retainment, _, _, _, _, _, Type), PropElem), !.
abutment_style(_, spill_through,none).

% ============================================================
% Number of Girders per Span
% ============================================================

% n_girders(+GirderType, +RoadwayWidth, -N)
% Ceiling division: enough girders to cover the full deck width.
n_girders(GirderType, RoadwayWidth, N) :-
    girder_props(GirderType, _, width(GW)),
    N is ceiling(RoadwayWidth / GW).


% ============================================================
% Solution Generator
% ============================================================

% solve_all(-Solutions)
% Each element: solution(NSpans, PropElem, BridgeLength,
%                        GirderType, SpanLengths, Piers)
solve_all(Solutions) :-
    findall(Sol, solve_one(Sol), Solutions).

% solve_one(-Solution)
% Backtracks over: nspan(N) x embankment geometry x span config
solve_one(solution(N, PropElem, BridgeLength, GirderType, SpanLengths, Piers)) :-
    nspan(N),
    % --- initialise dynamic state for this N ---
    retract_all_facts,
    assert_all_soil_logs,
    initial_bridge_length(BridgeLength0),
    estimate_bearing_x_load(N, BridgeLength0),
    compute_bearing_for_nspan(N, BridgeLength0, BearingElev, DepthFromRatio, SurfaceElev),
    assertz(initial_depth(N, DepthFromRatio)),
    assertz(surface(SurfaceElev)),
    assertz(soil_log(gravel, dense, SurfaceElev)),
    assert_soil_from_logs,
    % --- abutment geometry (backtracks over slope/confined combos) ---
    build_list(LayerList),
    bottom(BottomElev),
    iter_depth(LayerList, BottomElev, none, [[BottomElev, bottom]],
               Profile, _, _),
    compile_elements(Profile, DepthFromRatio, AbutElem),
    design_elements(AbutElem, PropElem),
    % --- bridge length from designed geometry ---
    bridge_length(PropElem, BridgeLength),
    % --- superstructure (voided_precast tried first) ---
    span_config(N, BridgeLength, GirderType, SpanLengths, NPiers),
    % --- piers ---
    bottom(BottomElev),
    pier_config(NPiers, BottomElev, BearingElev, Piers).

% ============================================================
% Pier Configuration
% pier_config(+NPiers, +BotElev, +BearingElev, -Piers)
% Piers are always pipe pile bents.
% ============================================================

pier_config(0, _, _, piers(0, none, 0, _, _)) :- !.
pier_config(NPiers, BotElev, BearingElev,
            piers(NPiers, pipe_pile_bent, Height, BotElev, BearingElev)) :-
    NPiers > 0,
    Height is BearingElev - BotElev.

% ============================================================
% Solution Printing
% ============================================================
% (Pricing predicates -- price_element/3, price_elements/3, price_pier/3,
% price_solution/3, girder_cost_items/5, sum_priced/2, solution_cost/2 --
% and all unit rates now live in price_list.)

% scour_label(+PropElem, -Label)
% Derives a scour protection label from the elements present in PropElem.
scour_label(PropElem, Label) :-
    ( member(elem(sheet_piling, _, _, _, _, _, _), PropElem) ->
        Label = 'scour: sheet piling + rip rap'
    ; member(elem(rip_rap, _, _, _, _, _, _), PropElem),
      member(elem(retainment, _, _, _, _, _, _), PropElem) ->
        Label = 'scour: extended wall + rip rap'
    ; member(elem(rip_rap, _, _, _, _, _, _), PropElem) ->
        Label = 'scour: rip rap on embankment'
    ;
        Label = ''
    ).

