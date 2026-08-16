% Bearing Capacity Calculation based on Canadian Foundation Engineering Manual 4th Edition, Section 10.2
:-module(cfem_4th_prolog_qu,[ultimate_bearing_capacity/8]).

% Assumes general shear failure for shallow foundations on uniform soil.
% Handles both drained and undrained conditions.
% Includes shape, depth, and surface slope modification factors (based on Vesic, 1975).
% Assumes no load inclination, no base tilt (S_i = 1, S_delta = 1).
% No eccentricity (B' = B, L' = L).
% For undrained: Use C = su (undrained shear strength), PhiDeg = 0.
% For drained: Use effective parameters C' and Phi'.
% Qs is vertical stress at foundation base (effective for drained, total for undrained).
% Gamma is unit weight (adjust for buoyancy if groundwater present).
% B is foundation width, L is foundation length (L >= B; for strip, use large L e.g., 1e6).
% D is embedment depth (default 0).
% BetaDeg is surface slope angle in degrees below horizontal away from foundation (default 0; beta < 45°).
% Angles in degrees for input.

deg_to_rad(Deg, Rad) :-
    Rad is Deg * pi / 180.

cot(X, Cot) :-
    X \= 0,
    Cot is 1 / tan(X).

% Bearing capacity factors - special case for PhiDeg = 0 to avoid division by zero
bearing_factors(0, BetaRad, Nc, Nq, Ngamma) :-
    Nc = 5.14,
    Nq = 1,
    (BetaRad > 0 ->
        Ngamma is -2 * sin(BetaRad)  % Special case for slope in undrained conditions
    ;   Ngamma = 0
    ),
    !.

bearing_factors(PhiDeg, _, Nc, Nq, Ngamma) :-
    PhiDeg \= 0,
    deg_to_rad(PhiDeg, Phi),
    HalfPhiDeg is PhiDeg / 2,
    deg_to_rad(45 + HalfPhiDeg, AngleRad),
    TanAngle is tan(AngleRad),
    Nq is exp(pi * tan(Phi)) * TanAngle * TanAngle,
    cot(Phi, CotPhi),
    Nc is (Nq - 1) * CotPhi,
    Ngamma is 0.0663 * exp(0.1623 * PhiDeg). %% assume rough interface

% Shape modification factors (S_cs, S_qs, S_gammas)
shape_factors(Nc, Nq, Phi, B, L, Scs, Sqs, Sgammas) :-
    Ratio is B / L,
    Scs is 1 + Ratio * (Nq / Nc),
    Sqs is 1 + Ratio * tan(Phi),
    Sgammas is 1 - 0.4 * Ratio.

% Depth modification factors (S_cd, S_qd, S_gammad)
depth_factors(PhiDeg, Nc, B, D, Scd, Sqd, Sgammad) :-
    deg_to_rad(PhiDeg, Phi),
    K_ratio is D / B,
    (K_ratio =< 1 -> K is K_ratio ; K is atan(K_ratio)),  % atan in radians
    Sqd is 1 + 2 * tan(Phi) * (1 - sin(Phi))**2 * K,
    Sgammad is 1,
    (PhiDeg =:= 0 ->
        Scd is 1 + 0.4 * K;   
        Scd is Sqd - (1 - Sqd) / (Nc * tan(Phi))).

% Surface slope modification factors (S_cbeta, S_qbeta, S_gammabeta)
slope_factors(PhiDeg, Nc, BetaRad, Scbeta, Sqbeta, Sgammabeta) :-
    deg_to_rad(PhiDeg, Phi),
    Sqbeta is (1 - tan(BetaRad))**2,
    Sgammabeta is (1 - tan(BetaRad))**2,
    (PhiDeg =:= 0 ->
        Scbeta is 1 - (2 * BetaRad) / (pi + 2);   
        Scbeta is Sqbeta - (1 - Sqbeta) / (Nc * tan(Phi))
    ).

% Ultimate bearing capacity qu (or Ru in LSD)
ultimate_bearing_capacity(C, PhiDeg, Gamma, B, L, D, BetaDeg, Qu) :-
    deg_to_rad(BetaDeg, BetaRad),
    bearing_factors(PhiDeg, BetaRad, Nc, Nq, Ngamma),
    deg_to_rad(PhiDeg, Phi),
    Qs is Gamma * D,  % Computed here as surcharge (overburden stress)
    shape_factors(Nc, Nq, Phi, B, L, Scs, Sqs, Sgammas),
    depth_factors(PhiDeg, Nc, B, D, Scd, Sqd, Sgammad),
    slope_factors(PhiDeg, Nc, BetaRad, Scbeta, Sqbeta, Sgammabeta),
    % Overall S
    Sc is Scs * Scd * Scbeta,
    Sq is Sqs * Sqd * Sqbeta,
    Sgamma is Sgammas * Sgammad * Sgammabeta,
    Term1 is C * Nc * Sc,
    Term2 is Qs * Nq * Sq,
    Term3 is 0.5 * Gamma * B * Ngamma * Sgamma,
    Qu is Term1 + Term2 + Term3.

% Example queries:
% Strip footing (large L), drained, D=0, Beta=0: ?- ultimate_bearing_capacity(0, 30, 18, 2, 100000, 0, 0, Qu).
% Square footing, undrained, D=1, Beta=0: ?- ultimate_bearing_capacity(50, 0, 18, 2, 2, 1, 0, Qu).
% With slope: ?- ultimate_bearing_capacity(0, 30, 18, 2, 2, 0, 10, Qu).