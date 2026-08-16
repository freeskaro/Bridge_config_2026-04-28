%this code is towards the developement of a truck loading analysis

%helper
select_last([H|T],Last,Rest):- append(Rest,[Last], [H|T]).

%% bridge length for a single span bridge
bridge_length(30).  % in meters

%% Truck axle weights, spacings, and axle numbers for a 5-axle truck.
truck([50,125,125,175,150]).
axle_spacing([3.6,1.2,6.6,6.6]).
axle_number([1,2,3,4,5]).

%% Trim truck axles from the back, then front, printing each configuration.
trim():-truck([H|T]),trim([H|T]).

% front_trim(+List)
% Prints List, then List with the front axle dropped, and so on, down to
% the single axle at the back of List (never touches the back itself).
front_trim([H]):- !, writeln('singl axle'),writeln(H).
front_trim([H|T]):- writeln([H|T]), front_trim(T).

% trim(+List)
% For the current back-trimmed truck, prints every front-trim of it, then
% drops the last axle and repeats -- until only a single axle is left.
trim([H]):- !, front_trim([H]).
trim([H|T]):- front_trim([H|T]), select_last([H|T],_Last,Rest), trim(Rest).

%% maximum reaction at support for a single span bridge
% for axle group,
% 1- confirm the length of the bridge is greater than the length of the group,
% 2- position the group such that the first axle is at the start of the bridge,
% 3- calculate reaction at support under first axle,
% 4- position the group such that the last axle is at the end of the bridge,
% 5- calculate reaction at support under last axle

% group_length(+Spacings, -Length)
% Total length spanned by the axle group (front axle to back axle).
group_length(Spacings, Length) :- sum_list(Spacings, Length).

% shift_positions(+Positions, +Shift, -ShiftedPositions)
shift_positions([], _, []).
shift_positions([P|Ps], Shift, [P2|P2s]) :-
    P2 is P + Shift,
    shift_positions(Ps, Shift, P2s).

% reaction_at_left_support(+Weights, +Positions, +BridgeLength, -Reaction)
% Reaction at the left support (x=0): each axle contributes Weight * (L-x)/L,
% the simply-supported-beam influence-line ordinate for the left support.
reaction_at_left_support([], [], _, 0).
reaction_at_left_support([W|Ws], [X|Xs], L, Reaction) :-
    reaction_at_left_support(Ws, Xs, L, Reaction0),
    Reaction is Reaction0 + W*(L-X)/L.

% reaction_at_right_support(+Weights, +Positions, +BridgeLength, -Reaction)
% Reaction at the right support (x=L): each axle contributes Weight * x/L.
reaction_at_right_support([], [], _, 0).
reaction_at_right_support([W|Ws], [X|Xs], L, Reaction) :-
    reaction_at_right_support(Ws, Xs, L, Reaction0),
    Reaction is Reaction0 + W*X/L.

% max_reaction_support(+Weights, +Spacings, +BridgeLength, -ReactionFront, -ReactionBack, -MaxReaction)
% ReactionFront: reaction at the near support with the first axle run up to
% the start of the bridge (steps 2-3). ReactionBack: reaction at the near
% support with the last axle run up to the end of the bridge (steps 4-5) --
% the mirror-image case. MaxReaction is the governing (larger) of the two.
max_reaction_support(Weights, Spacings, BridgeLength, ReactionFront, ReactionBack, MaxReaction) :-
    group_length(Spacings, GroupLen),
    BridgeLength >= GroupLen,                            % 1- group fits on the span
    axle_positions(Spacings, PositionsFront),             % 2- first axle at the start
    reaction_at_left_support(Weights, PositionsFront, BridgeLength, ReactionFront),  % 3
    Shift is BridgeLength - GroupLen,
    shift_positions(PositionsFront, Shift, PositionsBack),                          % 4- last axle at the end
    reaction_at_right_support(Weights, PositionsBack, BridgeLength, ReactionBack),  % 5
    MaxReaction is max(ReactionFront, ReactionBack).

% max_reaction_support(-MaxReaction)
% Convenience wrapper: runs the check above against the full truck.
max_reaction_support(MaxReaction) :-
    truck(Weights),
    axle_spacing(Spacings),
    bridge_length(BridgeLength),
    max_reaction_support(Weights, Spacings, BridgeLength, ReactionFront, ReactionBack, MaxReaction),
    format("reaction (first axle at start) = ~2f kN~n", [ReactionFront]),
    format("reaction (last axle at end)    = ~2f kN~n", [ReactionBack]),
    format("governing max reaction         = ~2f kN~n", [MaxReaction]).

% back_trim_group(+Weights, +Spacings, +AxleNumbers, -SubWeights, -SubSpacings, -SubAxleNumbers)
% Every group obtained by trimming zero or more axles (and their trailing
% spacings/axle numbers) off the BACK only, down to the single front axle.
back_trim_group(Weights, Spacings, AxleNumbers, Weights, Spacings, AxleNumbers).
back_trim_group(Weights, Spacings, AxleNumbers, SubW, SubS, SubA) :-
    Spacings \= [],
    select_last(Weights, _, W1),
    select_last(Spacings, _, S1),
    select_last(AxleNumbers, _, A1),
    back_trim_group(W1, S1, A1, SubW, SubS, SubA).

% front_trim_group(+Weights, +Spacings, +AxleNumbers, -SubWeights, -SubSpacings, -SubAxleNumbers)
% Every group obtained by trimming zero or more axles (and their leading
% spacings/axle numbers) off the FRONT only, down to the single back axle.
front_trim_group(Weights, Spacings, AxleNumbers, Weights, Spacings, AxleNumbers).
front_trim_group([_|Ws], [_|Ss], [_|As], SubW, SubS, SubA) :-
    front_trim_group(Ws, Ss, As, SubW, SubS, SubA).

% axle_group(+Weights, +Spacings, +AxleNumbers, -GroupWeights, -GroupSpacings, -GroupAxleNumbers)
% Every contiguous axle group: for each back-trim level, every front-trim
% of what's left -- exactly the groups trim/1 walks over, but bound to
% variables instead of printed. GroupAxleNumbers tracks which original
% axle numbers survive in the group, e.g. for checking "axles 1 to 3".
axle_group(Weights, Spacings, AxleNumbers, GroupWeights, GroupSpacings, GroupAxleNumbers) :-
    back_trim_group(Weights, Spacings, AxleNumbers, BackW, BackS, BackA),
    front_trim_group(BackW, BackS, BackA, GroupWeights, GroupSpacings, GroupAxleNumbers).

% max_reaction_all_groups(+BridgeLength, -BestGroupWeights, -BestReaction)
% Across every axle group that fits on a span of BridgeLength (groups too
% long for the span are skipped by max_reaction_support/6's own length
% check), the group and reaction that govern (the largest).
max_reaction_all_groups(BridgeLength, BestGroupWeights, BestReaction) :-
    truck(Weights),
    axle_spacing(Spacings),
    axle_number(AxleNumbers),
    findall(MaxR-GW,
            ( axle_group(Weights, Spacings, AxleNumbers, GW, GS, _GA),
              max_reaction_support(GW, GS, BridgeLength, _, _, MaxR)
            ),
            Pairs),
    Pairs \= [],
    keysort(Pairs, Sorted),
    last(Sorted, BestReaction-BestGroupWeights).

% max_reaction_all_groups(+BridgeLength)
% Prints the governing axle group and reaction for a given bridge span.
max_reaction_all_groups(BridgeLength) :-
    max_reaction_all_groups(BridgeLength, BestGroupWeights, BestReaction),
    format("governing axle group: ~w~n", [BestGroupWeights]),
    format("max reaction for ~wm span: ~2f kN~n", [BridgeLength, BestReaction]).


%%for maximum moment on single span
% for axle weights and spacings, 
% 1- calculate the truck centoid, 
% 2- position truck such that ceneter line of bridge is half way between truck centroid and heavier axle
% 3- caclulate moment under heavier axle
% NOT COMPLETE YET

% cumulative_positions(+Spacings, +Start, -Positions)
% Running distance from Start after each spacing in turn.
cumulative_positions([], _, []).
cumulative_positions([S|Ss], Acc, [Pos|Positions]) :-
    Pos is Acc + S,
    cumulative_positions(Ss, Pos, Positions).

% axle_positions(+Spacings, -Positions)
% Position of every axle along the truck, taking the first axle as the
% origin (0) and accumulating the spacings between successive axles.
axle_positions(Spacings, [0|Positions]) :-
    cumulative_positions(Spacings, 0, Positions).

% weighted_moment(+Weights, +Positions, -SumWP, -SumW)
% SumWP = sum of weight*position (moment about the origin), SumW = total weight.
weighted_moment([], [], 0, 0).
weighted_moment([W|Ws], [P|Ps], SumWP, SumW) :-
    weighted_moment(Ws, Ps, SumWP0, SumW0),
    SumWP is SumWP0 + W*P,
    SumW is SumW0 + W.

% truck_centroid(+Weights, -X)
% X is the position (measured from the first axle) of the resultant load
% -- the weight-averaged position of the axles in Weights, using the
% spacings in axle_spacing/1 to locate each axle.
truck_centroid(Weights, X) :-
    axle_spacing(Spacings),
    axle_positions(Spacings, Positions),
    weighted_moment(Weights, Positions, SumWP, SumW),
    X is SumWP / SumW.

% ============================================================
% Live Load Contribution to the Abutment Reaction (CHBDC)
%
% live load reaction = (max reaction from one truck, governing axle group)
%                       x (1 + dynamic load allowance)
%                       x number of design lanes
%                       x multi-lane modification factor
% ============================================================

deck_width(10). % Wc, m

% design_lanes(+DeckWidth, -N)  -- Table 3.5
design_lanes(Wc, 1) :- Wc =< 6.0, !.
design_lanes(Wc, 2) :- Wc =< 10.0, !.
design_lanes(Wc, 3) :- Wc =< 13.5, !.
design_lanes(Wc, 4) :- Wc =< 17.0, !.
design_lanes(Wc, 5) :- Wc =< 20.5, !.
design_lanes(Wc, 6) :- Wc =< 24.0, !.
design_lanes(Wc, 7) :- Wc =< 27.5, !.
design_lanes(_, 8).

% multi_lane_factor(+N, -Factor)  -- Table 3.6
multi_lane_factor(1, 1.00) :- !.
multi_lane_factor(2, 0.90) :- !.
multi_lane_factor(3, 0.80) :- !.
multi_lane_factor(4, 0.70) :- !.
multi_lane_factor(5, 0.60) :- !.
multi_lane_factor(_, 0.55).

% dynamic_load_allowance(+GroupAxleNumbers, -DLA)  -- Clause 3.8.4.5.3 (b,c,d)
% b) one axle used                                   -> 0.40
% c) two axles, or exactly axles 1 to 3               -> 0.30
% d) three axles other than 1-3, or more than three   -> 0.25
dynamic_load_allowance(AxleNumbers, DLA) :-
    length(AxleNumbers, NumAxles),
    (   NumAxles =:= 1 -> DLA = 0.40
    ;   NumAxles =:= 2 -> DLA = 0.30
    ;   NumAxles =:= 3, AxleNumbers == [1,2,3] -> DLA = 0.30
    ;   DLA = 0.25
    ).

% live_load_abutment_reaction(+BridgeLength, -BestGroupWeights, -BestGroupAxleNumbers, -LiveLoadReaction)
% Governs across every axle group: static reaction x (1+DLA) for that
% group -- the DLA depends on how many, and which, axles are in the
% governing group, so a smaller group with a bigger DLA can still win.
% The result is then scaled by the number of design lanes and the
% multi-lane modification factor (Tables 3.5/3.6).
live_load_abutment_reaction(BridgeLength, BestGroupWeights, BestGroupAxleNumbers, LiveLoadReaction) :-
    truck(Weights),
    axle_spacing(Spacings),
    axle_number(AxleNumbers),
    findall(Factored-group(GW,GA),
            ( axle_group(Weights, Spacings, AxleNumbers, GW, GS, GA),
              max_reaction_support(GW, GS, BridgeLength, _, _, MaxR),
              dynamic_load_allowance(GA, DLA),
              Factored is MaxR * (1 + DLA)
            ),
            Pairs),
    Pairs \= [],
    keysort(Pairs, Sorted),
    last(Sorted, BestFactored-group(BestGroupWeights, BestGroupAxleNumbers)),
    deck_width(Wc),
    design_lanes(Wc, N),
    multi_lane_factor(N, ModFactor),
    LiveLoadReaction is BestFactored * N * ModFactor.

% live_load_abutment_reaction(+BridgeLength)
% Prints the governing axle group and the live-load abutment reaction.
live_load_abutment_reaction(BridgeLength) :-
    live_load_abutment_reaction(BridgeLength, BestGroupWeights, BestGroupAxleNumbers, LiveLoadReaction),
    deck_width(Wc), design_lanes(Wc, N), multi_lane_factor(N, ModFactor),
    format("governing axle group: ~w (axles ~w)~n", [BestGroupWeights, BestGroupAxleNumbers]),
    format("design lanes = ~w, modification factor = ~w~n", [N, ModFactor]),
    format("live load abutment reaction for ~wm span: ~2f kN~n", [BridgeLength, LiveLoadReaction]).