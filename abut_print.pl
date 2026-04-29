% abut_print.pl
%
% All output predicates: soil/fact echoing, element summaries, and solution reporting.
% Consulted by abut_soil_config_8; transitively available to prolog_bridge_config.

% ============================================================
% Soil and Dynamic Fact Echoing
% ============================================================

% Print all currently asserted soil(Type, Density, Elev) facts.
echo_soil_facts :-
    forall(soil(Type, Density, Elev),
           format('soil(~w, ~w, ~1f).~n', [Type, Density, Elev]) ).

% Print all currently asserted dynamic facts.
echo_all_facts :-
    writeln('--- surface/1 ---'),
    forall(surface(Elev),
           format('surface(~1f).~n', [Elev])),
    writeln('--- initial_depth/2 ---'),
    forall(initial_depth(N, Depth),
           format('initial_depth(~w, ~1f).~n', [N, Depth])),
    writeln('--- soil_log/3 ---'),
    forall(soil_log(Type, Density, Elev),
           format('soil_log(~w, ~w, ~1f).~n', [Type, Density, Elev])),
    writeln('--- soil/3 ---'),
    forall(soil(Type, Density, Elev),
           format('soil(~w, ~w, ~1f).~n', [Type, Density, Elev])).

% ============================================================
% Element Summary
% ============================================================

% print_solution_summary(+PropElem)
%
% Writes a human-readable bullet list of each element: type,
% bottom/top elevations, base width (except embankment), and
% for pile elements: piles per row and row spacing.

print_solution_summary(PropElem) :-
    writeln('Elements:'),
    maplist(print_elem_line, PropElem).

% Pile element: elem(piles, RowCounts, Spacings, none, none, none, none)
print_elem_line(elem(piles, RowCounts, Spacings, _, _, _, _)) :-
    format("  - piles:~n"),
    print_pile_rows(1, RowCounts, Spacings).

print_pile_rows(_, [], _).
print_pile_rows(I, [N|Ns], [X|Xs]) :-
    format("      row ~w: ~w piles at ~2f m~n", [I, N, X]),
    I1 is I + 1,
    print_pile_rows(I1, Ns, Xs).

% Embankment: no B
print_elem_line(elem(embankment, _, BotElev, _, TopElev, _, _)) :-
    format("  - embankment: elev ~2f to ~2f m~n", [BotElev, TopElev]).

% Sheet piling: elem(sheet_piling, BotX, BotElev, BotX, TopElev, 0, none)
print_elem_line(elem(sheet_piling, _, BotElev, _, TopElev, _, _)) :-
    H is TopElev - BotElev,
    format("  - sheet piling: depth ~1f m (elev ~1f to ~1f m)~n", [H, BotElev, TopElev]).

% Rip rap: elem(rip_rap, RefX, RiverbedElev, RefX, RiverbedElev, Extent, none)
print_elem_line(elem(rip_rap, _, BotElev, _, _, Extent, _)) :-
    format("  - rip rap: ~1f m extent at riverbed elev ~1f m~n", [Extent, BotElev]).

% All other elements: elem(Type, BotX, BotElev, TopX, TopElev, B, WallType)
print_elem_line(elem(Type, _, BotElev, _, TopElev, B, _)) :-
    Type \== piles, Type \== embankment,
    Type \== sheet_piling, Type \== rip_rap,
    format("  - ~w: elev ~1f to ~1f m, B = ~2f m~n",
           [Type, BotElev, TopElev, B]).

% ============================================================
% Solution Reporting
% ============================================================

% print_priced_items(+PricedItems, +RunningTotal, -FinalTotal)
print_priced_items([], Total, Total).
print_priced_items([priced(_, Label, Cost) | Rest], Acc, Final) :-
    CostR is round(Cost),
    format("    ~w  $~:d~n", [Label, CostR]),
    Acc2 is Acc + Cost,
    print_priced_items(Rest, Acc2, Final).

print_solution(Sol) :-
    Sol = solution(N, PropElem, BridgeLength, GirderType, SpanLengths, Piers),
    abutment_style(PropElem, AbutStyle, WallType),
    scour_label(PropElem, ScourLabel),
    price_solution(Sol, PricedItems, TotalCostRaw),
    TotalCost is round(TotalCostRaw),
    Piers = piers(NP, _, PH, _, _),
    ( ScourLabel == '' ->
        format("~n=== ~w-span | ~1f m | ~w ===~n",
               [N, BridgeLength, GirderType])
    ;
        format("~n=== ~w-span | ~1f m | ~w | ~w ===~n",
               [N, BridgeLength, GirderType, ScourLabel])
    ),
    format("  Abutment style: ~w (~w)~n", [AbutStyle, WallType]),
    ( ScourLabel \== '' ->
        format("  Scour protection: ~w~n", [ScourLabel])
    ; true ),
    format("  Spans (m): ~w~n", [SpanLengths]),
    ( NP =:= 0 ->
        format("  Piers: none~n")
    ;
        format("  Piers: ~w x pipe_pile_bent, height ~1f m~n", [NP, PH])
    ),
    format("  --- Cost Breakdown ---~n"),
    print_priced_items(PricedItems, 0, _),
    format("  ~n"),
    format("  TOTAL:  $~:d~n", [TotalCost]),
    print_solution_summary(PropElem).

print_all_solutions([]).
print_all_solutions([S | Rest]) :-
    print_solution(S),
    print_all_solutions(Rest).
