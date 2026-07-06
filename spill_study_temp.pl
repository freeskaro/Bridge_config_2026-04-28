:- consult('prolog_bridge_config').
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

% retwall_height(+Sol, -H)
% Height of the retaining wall element in a solution (TopElev - BotElev).
retwall_height(solution(_,P,_,_,_,_), H) :-
    member(elem(retainment, _, BotElev, _, TopElev, _, _), P),
    H is TopElev - BotElev.

% "modified spill-through" threshold: a winning retaining-wall solution
% whose actual wall is shorter than this is structurally almost a
% spill-through design (nearly all the height is embankment fill, with
% only a short confined-wall stub near the bottom) -- see the H=7,
% loose/dense-soil timber_crib example from this conversation.
modified_spill_through_height_threshold(2.0).

run_combo(H, Density, RockDBelow, HO) :-
    ApproachElev = 100,
    Bottom is ApproachElev - H,
    RockElev is Bottom - RockDBelow,
    retractall(bottom(_)), assertz(bottom(Bottom)),
    retractall(hydraulic_opening(_)), assertz(hydraulic_opening(HO)),
    retractall(soil_log1(_,_,_)),
    assertz(soil_log1(gravel, Density, ApproachElev)),
    assertz(soil_log1(rock, sound, RockElev)),
    ( catch(solve_all(Solutions), _, Solutions=[]) ->
        true
    ;   Solutions = []
    ),
    ( Solutions == [] ->
        format("H=~w soil=~w rockD=~w HO=~w | NO SOLUTIONS~n",[H,Density,RockDBelow,HO])
    ;
        findall(Cost-Sol, (member(Sol,Solutions), price_solution(Sol,_,Cost)), AllPairs),
        keysort(AllPairs, AllSorted),

        ( findall(C-S, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), abutment_style(P,St,_), St==spill_through), SpillList), SpillList=[SC-_|_] -> true ; SC=none ),
        ( findall(C-S, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), abutment_style(P,St,WT), St==earth_retaining, WT==concrete_gravity, \+ member(elem(embankment,_,_,_,_,_,_),P), \+ member(elem(stub_abutment,_,_,_,_,_,_),P)), FHList), FHList=[FC-_|_] -> true ; FC=none ),
        ( findall(C-S, (member(C-S,AllSorted), S=solution(_,P,_,_,_,_), abutment_style(P,St,WT), St==earth_retaining, \+ (WT==concrete_gravity, \+ member(elem(embankment,_,_,_,_,_,_),P), \+ member(elem(stub_abutment,_,_,_,_,_,_),P))), RetList), RetList=[RC-RS|_] -> true ; RC=none, RS=none ),

        % Relabel the retwall winner as "modified spill-through" if its
        % actual wall is shorter than the threshold.
        ( RS == none -> RCLabel = none
        ; retwall_height(RS, WallH), modified_spill_through_height_threshold(Thresh), WallH < Thresh ->
            RCLabel = modified_spill
        ; RCLabel = retwall
        ),

        winner_label(SC, RC, RCLabel, FC, Winner),
        format("H=~w soil=~w rockD=~w HO=~w | spill=~w retwall(~w)=~w fullht=~w | WINNER=~w~n",
               [H,Density,RockDBelow,HO,SC,RCLabel,RC,FC,Winner])
    ).

% winner_label(+SpillCost, +RetWallCost, +RetWallLabel, +FullHtCost, -Label)
% Cheapest of the three categories (none = no solution found in that category).
% RetWallLabel is either retwall or modified_spill, per run_combo/4's height check.
winner_label(SC, RC, RCLabel, FC, Winner) :-
    findall(C-Cat, ( member(C-Cat, [SC-spill, RC-RCLabel, FC-fullht]), number(C) ), Pairs),
    ( Pairs == [] -> Winner = none
    ; keysort(Pairs, [_-Winner|_])
    ).

run_study :-
    setup_nspan1,
    setup_mse25,
    forall(member(H,[5,7,9]),
      forall(member(Density,[loose,medium,dense]),
        forall(member(RockD,[0,2,4,6,8,10]),
          run_combo(H, Density, RockD, 15)))).
