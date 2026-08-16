:- consult('prolog_bridge_config.pl').

:- dynamic(soil_log1/3).

setup_soil :-
    retractall(soil_log1(_,_,_)),
    assertz(soil_log1(gravel, loose,  100.0)),
    assertz(soil_log1(gravel, loose,   97.0)),
    assertz(soil_log1(gravel, medium,  95.5)),
    assertz(soil_log1(gravel, medium,  93.0)),
    assertz(soil_log1(rock,   sound,   85.0)).

is_full_height(P) :-
    abutment_style(P, earth_retaining, concrete_gravity),
    \+ member(elem(embankment,_,_,_,_,_,_), P),
    \+ member(elem(stub_abutment,_,_,_,_,_,_), P).

run :-
    setup_soil,
    ( catch(solve_all(Solutions), Err, (print_message(error, Err), Solutions=[])) -> true ; Solutions = [] ),
    length(Solutions, NSol),
    format("~n>>> Total solutions found: ~w~n~n", [NSol]),
    findall(Cost-Sol, (member(Sol,Solutions), catch(price_solution(Sol,_,Cost),_,fail)), Pairs),
    keysort(Pairs, Sorted),
    format("~n============ ALL SOLUTIONS (sorted by cost) ============~n"),
    forall(member(C-S, Sorted),
        ( S = solution(N,P,BL,GT,SL,_),
          abutment_style(P, St, WT),
          format("~w-span, cost=$~0f, style=~w/~w, len=~1f, girder=~w, spans=~w~n",
                 [N,C,St,WT,BL,GT,SL])
        )),

    % Cheapest overall
    Sorted = [CheapCost-CheapSol|_],
    format("~n============ 1) CHEAPEST OVERALL ============~n"),
    print_solution(CheapSol),
    format("~nTOTAL COST CHECK: ~0f~n", [CheapCost]),

    % Full-height standard concrete gravity wall (no embankment/stub, reaches surface)
    format("~n============ 2) FULL-HEIGHT CONCRETE GRAVITY WALL ============~n"),
    ( findall(C-S, (member(C-S,Sorted), S=solution(_,P,_,_,_,_), is_full_height(P)), FHList), FHList=[FC-FS|_] ->
        print_solution(FS), format("~nTOTAL COST CHECK: ~0f~n", [FC])
    ; format("NONE FOUND~n") ),

    % Spill-through (cheapest, any span count)
    format("~n============ 3) SPILL-THROUGH ABUTMENTS ============~n"),
    ( findall(C-S, (member(C-S,Sorted), S=solution(_,P,_,_,_,_), abutment_style(P,St,_), St==spill_through), SpillList), SpillList=[SC-SS|_] ->
        print_solution(SS), format("~nTOTAL COST CHECK: ~0f~n", [SC])
    ; format("NONE FOUND~n") ),

    % 2-span spill-through (cheapest)
    format("~n============ 4) 2-SPAN SPILL-THROUGH ============~n"),
    ( findall(C-S, (member(C-S,Sorted), S=solution(N2,P,_,_,_,_), N2=:=2, abutment_style(P,St2,_), St2==spill_through), Spill2List), Spill2List=[SC2-SS2|_] ->
        print_solution(SS2), format("~nTOTAL COST CHECK: ~0f~n", [SC2])
    ; format("NONE FOUND~n") ),

    true.

:- initialization(main).
main :- catch(run, E, (print_message(error,E), halt(1))). %, halt.
