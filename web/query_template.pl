% query_template.pl
%
% Symlinked (unchanged) into each per-request temp directory created by
% web/runner.py, alongside symlinks to the solver source files and a
% freshly generated site_facts.pl holding that request's inputs. Consults
% the solver, runs it under a time limit, and prints a plain-text report
% to stdout for the Flask app to capture and display.

:- consult('prolog_bridge_config.pl').
:- use_module(library(time)).

is_full_height(P) :-
    abutment_style(P, earth_retaining, concrete_gravity),
    \+ member(elem(embankment,_,_,_,_,_,_), P),
    \+ member(elem(stub_abutment,_,_,_,_,_,_), P).

run :-
    catch(
        ( % The search itself (abut_pile_fallback.pl, abut_tree_gravity.pl,
          % etc.) format/2's a lot of diagnostic noise ("Pile solution
          % found: ...", "B = ...") straight to stdout as it explores
          % candidates. with_output_to discards that -- only the report
          % printed below, after solving, reaches real stdout.
          with_output_to(string(_), call_with_time_limit(30, solve_all(Solutions0)))
        -> Outcome = ok(Solutions0)
        ;  Outcome = failed
        ),
        time_limit_exceeded,
        Outcome = timeout
    ),
    handle_outcome(Outcome).

handle_outcome(timeout) :-
    format("~n>>> TIMEOUT: computation exceeded the 30-second limit. Try fewer soil layers or a narrower elevation / hydraulic-opening range.~n").
handle_outcome(failed) :-
    format("~n>>> No valid configurations were found for this site. Try widening the hydraulic opening, adjusting elevations, or revising the soil profile.~n").
handle_outcome(ok(Solutions)) :-
    length(Solutions, NSol),
    ( NSol =:= 0
    -> format("~nNo valid configurations were found for this site. Try widening the hydraulic opening, adjusting elevations, or revising the soil profile.~n")
    ;  report(Solutions)
    ).

report(Solutions) :-
    findall(Cost-Sol,
            (member(Sol, Solutions), catch(price_solution(Sol, _, Cost), _, fail)),
            Pairs),
    keysort(Pairs, Sorted),
    ( Sorted == []
    -> format("~n>>> ~w solution(s) were found but none could be priced (internal error in price_solution).~n", [Solutions])
    ;  report_sorted(Sorted)
    ).

report_sorted(Sorted) :-
    Sorted = [CheapCost-CheapSol|_],
    format("============ 1) CHEAPEST OVERALL ============~n"),
    print_solution(CheapSol),
    format("~nTOTAL COST CHECK: $~0f~n", [CheapCost]),

    format("~n============ 2) FULL-HEIGHT CONCRETE GRAVITY WALL ============~n"),
    ( findall(C-S, (member(C-S,Sorted), S=solution(_,P,_,_,_,_), is_full_height(P)), FHList), FHList=[FC-FS|_]
    -> print_solution(FS), format("~nTOTAL COST CHECK: $~0f~n", [FC])
    ;  format("NONE FOUND~n")
    ),

    format("~n============ 3) SPILL-THROUGH ABUTMENTS ============~n"),
    ( findall(C-S, (member(C-S,Sorted), S=solution(_,P,_,_,_,_), abutment_style(P,St,_), St==spill_through), SpillList), SpillList=[SC-SS|_]
    -> print_solution(SS), format("~nTOTAL COST CHECK: $~0f~n", [SC])
    ;  format("NONE FOUND~n")
    ),

    format("~n============ 4) 2-SPAN SPILL-THROUGH ============~n"),
    ( findall(C-S, (member(C-S,Sorted), S=solution(N2,P,_,_,_,_), N2=:=2, abutment_style(P,St2,_), St2==spill_through), Spill2List), Spill2List=[SC2-SS2|_]
    -> print_solution(SS2), format("~nTOTAL COST CHECK: $~0f~n", [SC2])
    ;  format("NONE FOUND~n")
    ).

% initialization(main) runs main once loading completes. main is written
% so every path -- success, a caught exception, or a plain goal failure
% -- still reaches halt/0: this process must never fall through to an
% interactive top level and hang, since it is invoked from a public,
% unauthenticated web endpoint with nothing attached to stdin.
:- initialization(main).
main :-
    ( catch(run, E, (print_message(error, E), format("~n>>> Internal error while solving: ~q~n", [E])))
    -> true
    ;  format("~n>>> Internal error: the solver failed unexpectedly.~n")
    ),
    halt.
