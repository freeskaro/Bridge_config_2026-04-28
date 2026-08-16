% Abut_tree_footing_def.pl
%
% Elastic settlement of a flexible strip foundation on a finite uniform layer.
% Formula:  S = q * B * I_s / E
%
% Reference: CEFM 4th section 11.3.4
%             influence factor table digitised from figure 11.1
%            (strip footing, L/B → ∞, surface foundation D = 0).
%
% Public interface: settlement_strip/5

:- module(abut_tree_footing_def, [settlement_strip/5]).


% ============================================================
% Settlement
% ============================================================

% settlement_strip(+Q, +B, +H, +E, -S)
%
%   Q  — applied pressure (kPa)
%   B  — footing width    (m)
%   H  — layer thickness  (m)
%   E  — elastic modulus  (kPa)
%   S  — centre settlement (mm)
settlement_strip(S, Q, B, H, E) :-
    HB is H / B,
    influence_factor(HB, Is),
    S is Q * B * Is / E *1000 .


% ============================================================
% Influence Factor
% ============================================================

% influence_factor(+HB, -Is)
% Interpolates I_s from the look-up table for a given H/B ratio.
% Asymptote: I_s → 1.8 as H/B → ∞ (represented by the sentinel entry).
influence_factor(HB, Is) :-
    influence_table(Points),
    interpolate(Points, HB, Is).

% influence_table(-Points)
% Digitised [H/B, I_s] pairs for a strip footing (approximate).
influence_table([
    [0,     0.00],  % sentinel: H/B → 0 -- rigid layer (rock) right at the
                     % footing base, no compressible material left to settle
    [0.10,  0.90],
    [0.25,  0.95],
    [0.50,  1.00],
    [1.00,  1.10],
    [2.50,  1.30],
    [5.00,  1.50],
    [1000,  1.80]   % sentinel: represents H/B → ∞
]).


% ============================================================
% Linear Interpolation
% ============================================================

% interpolate(+Points, +X, -Y)
% Linear interpolation over a sorted list of [X, Y] pairs.
% Fails if X is outside the table range (no silent extrapolation).
interpolate([[X1, Y1], [X2, Y2] | _], X, Y) :-
    X >= X1, X =< X2,
    !,
    Y is Y1 + (Y2 - Y1) * (X - X1) / (X2 - X1).
interpolate([_ | Tail], X, Y) :-
    interpolate(Tail, X, Y).