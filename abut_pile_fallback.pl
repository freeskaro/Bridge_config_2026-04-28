% abut_pile_fallback.pl
%
% Integrates pile design with the retaining wall workflow.
%
% Logic:
%   1. design_wall/11 (abut_tree_gravity) attempts a footing solution.
%   2. If settlement (S) or bearing capacity (Qr) checks fail for all B,
%      wall_design_or_piles/11 falls back to pile design.
%   3. The pile search tries increasing B values; for each B, it computes
%      Pcf, Mcf, Vcf at the centre of the wall base and calls best_config.
%
% vcf, pcf, mcf are the shear, vertical, and moment resultants at the
% centre of the bottom of the retaining wall — taken directly from the
% wall equilibrium calculation in abut_tree_gravity.
%
% Drop-in replacement for wall_design/11 in abut_soil_config_8:
%   Replace the call to wall_design/11 with wall_design_or_piles/11.

:- use_module('abut_tree_gravity',      [design_wall/11, equilibrium/4,
                                         soil_at_or_above/3, ka/5,
                                         pa_components/5, eccentricity/7]).
:- use_module('Abut_tree_footing_def',  [settlement_strip/5]).
:- use_module('CFEM_4th_prolog_qu',     [ultimate_bearing_capacity/8]).


% ============================================================
% Pile Design Parameters  (override per project)
% ============================================================

pile_incl(3.5).          % inclination factor for inclined piles
pile_pmax(1300).         % maximum allowable pile load (kN)
pile_hlat(125).          % maximum allowable lateral load per pile (kN)
pile_mc_threshold(50).   % Mc below which centroid formula applies (kNm)

n1_range([4,6,8,10,12,14]).
n2_range([4,6,8,10,12]).
n3_range([4,6,8,10,12]).
dias([0.3,0.4,0.5,0.6]).
x1min(0.450).


% ============================================================
% Top-level: try footing first, fall back to piles
% ============================================================

% wall_design_or_piles(+Above, -H, -B, -W, -SumM, -E,
%                      +Curr, +Below, +AllowS, +BearingLoad, -Processed, -PilesElem)
%
% PilesElem = none
%     when a footing solution is found.
% PilesElem = elem(piles, RowCounts, none, none, none, none, none)
%     when the pile fallback is used, where RowCounts = [N1], [N1,N2], or [N1,N2,N3].
%
% Pile fallback is only attempted for concrete_gravity walls.
% For all other wall types, failure here causes the caller to backtrack
% and try the next wall type from retaining_wall_type/1.

wall_design_or_piles(Above, H, B, W, SumM, E,
                     Curr, Below, AllowS, BearingLoad, Processed, PilesElem) :-
    Curr = elem(Elem, BotX, BotElev, TopX, TopElev, _, WallType),
    H is TopElev - BotElev,

    ( design_wall(Above, Below, TopElev, BotElev, H, BearingLoad,
                  B, W, SumM, E, AllowS)
    ->  % Footing solution found — build Processed directly from already-bound outputs.
        X2 is BotX - 1.5,
        Processed = elem(Elem, BotX, BotElev, X2, TopElev, B, WallType),
        PilesElem = none

    ;   % Footing failed — pile fallback is only valid for concrete gravity walls.
        WallType == concrete_gravity,
        %format("~n*** Footing failed (S or Qr). Trying pile foundation. ***~n"),
        pile_fallback(Above, H, B, Below, BotElev, BearingLoad,
                      Curr, WallType, Processed, PilesElem)
    ).


% ============================================================
% Pile Fallback
% ============================================================

% pile_fallback(+Above, +H, -B, +Below, +BotElev, +BearingLoad,
%               +Curr, +WallType, -Processed, -PilesElem)
%
% Iterates B (wall base width) in 0.5 m steps.
% For each B, derives Pcf/Mcf/Vcf from the wall equilibrium and
% searches for the best pile configuration.
% PilesElem = elem(piles, RowCounts, none, none, none, none, none) on success,
%             where RowCounts = [N1], [N1,N2], or [N1,N2,N3].

pile_fallback(Above, H, B, Below, BotElev, BearingLoad,
              Curr, WallType, Processed, PilesElem) :-
    Curr = elem(Elem, BotX, _, TopX, TopElev, _, _),

    % Iterate B until a pile solution is found.
    StartB is H / 4,
    between(0, 20, I),
    B is StartB + I * 0.5,

    % Wall forces at this B (same geometry as gravity wall).
    DeltaDeg is 0,
    ( Above == embankment -> BetaDeg is 26.6 ; BetaDeg is 0 ),
    soil_at_or_above(BotElev, Type, Des),
    friction_angle(Type, Des, PhiDeg),
    ka(90, BetaDeg, PhiDeg, DeltaDeg, Ka),
    pa_components(H, Ka, DeltaDeg, PaH, PaV),

    % Resultant at wall base centre = (Pcf, Vcf, Mcf).
    % eccentricity/7 returns WallV (total vertical reaction) and WallSumM
    % (moment about toe); from those we derive Pcf, Vcf, Mcf.
    eccentricity(H, B, PaH, PaV, WallV, WallSumM, _E0),

    % Pcf  = total vertical reaction including the bearing load.
    Pcf is WallV + BearingLoad,

    % Vcf  = horizontal reaction = PaH (DeltaDeg = 0, so PaV = 0).
    Vcf is PaH,

    % Mcf  = moment about base centre (toe moment minus V * B/2).
    SumMtoe is WallSumM + 0.6 * BearingLoad,
    Mcf is SumMtoe - Pcf * (B / 2),

    %format("~nTrying pile config for B = ~1f m~n", [B]),
    %format("  Pcf = ~1f kN,  Mcf = ~1f kNm,  Vcf = ~1f kN~n", [Pcf, Mcf, Vcf]),

    % Search for the best pile configuration.
    ( best_pile_config(B, Pcf, Mcf, Vcf,
                       Rows, X1, X2, X3, N1, N2, N3, P1, P3, Hi, Nt)
    ->  format("  Pile solution found: ~w rows, Nt=~w, P1=~1f kN, P3=~1f kN, Hi=~1f kN~n",
               [Rows, Nt, P1, P3, Hi]),
        X2new is BotX - 1.5,
        Processed = elem(Elem, BotX, BotElev, X2new, TopElev, B, WallType),
        ( Rows =:= 1 -> RowCounts = [N1]
        ; Rows =:= 2 -> RowCounts = [N1, N2]
        ;               RowCounts = [N1, N2, N3]
        ),
        PilesElem = elem(piles, RowCounts, none, none, none, none, none)
    ),
    !.   % commit to first B that yields a pile solution


% ============================================================
% Pile Configuration Search
% ============================================================

% best_pile_config(+B, +Pcf, +Mcf, +Vcf,
%                  -Rows, -X1, -X2, -X3,
%                  -N1, -N2, -N3, -P1, -P3, -Hi, -MinNt)
%
% Finds the configuration with the fewest piles, then the lowest P1.
% B is used here as the pile cap width (same as wall base width).

best_pile_config(B, Pcf, Mcf, Vcf,
                 Rows, X1, X2, X3, N1, N2, N3, P1, P3, Hi, MinNt) :-
    aggregate_all(min(Nt),
        check_pile_config(B, Pcf, Mcf, Vcf, _,_,_,_,_,_,_,_,_,_,Nt),
        MinNt),
    aggregate_all(min(P1v),
        check_pile_config(B, Pcf, Mcf, Vcf, _,_,_,_,_,_,_,P1v,_,_,MinNt),
        MinP1),
    check_pile_config(B, Pcf, Mcf, Vcf,
                      Rows, X1, X2, X3, N1, N2, N3, P1, P3, Hi, MinNt),
    P1 =:= MinP1,
    !.


% check_pile_config(+B, +Pcf, +Mcf, +Vcf,
%                   -Rows, -X1, -X2, -X3,
%                   -N1, -N2, -N3, -P1, -P3, -Hi, -Nt)

check_pile_config(B, Pcf, Mcf, Vcf,
                  Rows, X1, X2, X3, N1, N2, N3, P1, P3, Hi, Nt) :-

    % --- geometry ---
    pile_spacing(B, Rows, X1, X2raw, X3raw, _Dia),
    (X2raw = none -> X2 = 0.0 ; X2 = X2raw),
    (X3raw = none -> X3 = 0.0 ; X3 = X3raw),

    % --- pile counts + inclined counts ---
    pile_numbers(Rows, N1, N2, N3, Ni1, Ni2),

    % --- centroid & moment arms ---
    pile_centroid(B, X1, X2, X3, N1, N2, N3, Xc, R1, R2, R3, SumR2),

    % --- applied loads ---
    pile_incl(Incl),
    Nt  is N1 + N2 + N3,
    De  is B/2 - Xc,
    Mc  is Mcf - Pcf * De,   % moment corrected for centroid offset

    % --- load formula ---
    pile_mc_threshold(Thresh),
    (   Rows =:= 1, abs(Mc) < Thresh, SumR2 =:= 0.0
    ->  P1 is Pcf / Nt, P2 is P1, P3 is P1
    ;   SumR2 > 0,
        P1 is Pcf/Nt + Mc*R1/SumR2,
        P2 is Pcf/Nt + Mc*R2/SumR2,
        P3 is Pcf/Nt + Mc*R3/SumR2
    ),

    % --- capacity checks (fail fast) ---
    pile_pmax(Pmax), P1 < Pmax,
    P3 > -100,

    % --- lateral check ---
    Ht is (P1*Ni1 + P2*Ni2) / Incl,
    Hi is (Vcf - Ht) / Nt,
    pile_hlat(Hlat), Hi < Hlat.


% ============================================================
% Pile Spacing  (now takes B as first arg)
% ============================================================

% 1 row: single row at mid-width
pile_spacing(B, 1, X1, none, none, _) :-
    X1 is B / 2.

% 2 rows
pile_spacing(B, 2, X1, X2, none, Dia) :-
    dia(Dia),
    x1min(Xmin),
    candidate_dx(Dia, Dx),
    candidate_x1(X1),
    X2 is X1 + Dx,
    B >= X2 + Xmin.

% 3 rows
pile_spacing(B, 3, X1, X2, X3, Dia) :-
    dia(Dia),
    candidate_dx(Dia, Dx),
    candidate_x1(X1),
    X2 is X1 + Dx,
    valid_x3(B, X2, Dia, X3).


% ============================================================
% Pile Numbers + Inclined Counts
% ============================================================

pile_numbers(1, N1, 0,  0,  Ni1, 0) :-
    n1_range(NN1), member(N1, NN1),
    Ni1 is N1 // 2.

pile_numbers(2, N1, N2, 0,  N1,  0) :-
    n1_range(NN1), member(N1, NN1),
    n2_range(NN2), member(N2, NN2),
    N1 >= N2.

pile_numbers(3, N1, N2, N3, N1, N2) :-
    n1_range(NN1), member(N1, NN1),
    n2_range(NN2), member(N2, NN2), N1 >= N2,
    n3_range(NN3), member(N3, NN3).


% ============================================================
% Geometry Helpers
% ============================================================

dia(Dia)             :- dias(Dias), member(Dia, Dias).
candidate_dx(Dia, Dx):- member(M, [3,4,5,6]), Dx is M * Dia.
candidate_x1(X1)     :- x1min(Xmin), member(X1, [Xmin]).

% valid_x3(+B, +X2, +Dia, -X3)
% X3 is measured from the front of the cap: B - cover - offset.
valid_x3(B, X2, Dia, X3) :-
    x1min(X),
    member(Off, [0.0, 0.5]),
    X3 is B - X - Off,
    X3 - X2 > 3 * Dia.


% ============================================================
% Centroid & Moment Arms
% ============================================================

pile_centroid(B, X1, X2, X3, N1, N2, N3, Xc, R1, R2, R3, SumR2) :-
    Nt is N1 + N2 + N3, Nt > 0,
    Xc    is (N1*X1 + N2*X2 + N3*X3) / Nt,
    Half  is B / 2,
    De    is Half - Xc,
    R1    is Half - X1 - De,
    R2    is Half - X2 - De,
    R3    is Half - X3 - De,
    SumR2 is N1*R1**2 + N2*R2**2 + N3*R3**2.
