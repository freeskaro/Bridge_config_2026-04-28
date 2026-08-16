% bridge_facts
%
% Superstructure product catalogue: physical properties only.
% These are standard/cross-project values; edit to add new girder/pile
% products. Unit prices and pricing predicates live in price_list.
%
% Contents:
%   - Girder available lengths and section properties
%   - Pile diameter catalogue and layout geometry
%   - Superstructure dead weight (for load calculations)

% ============================================================
% Girder Types  (preferred order — cheapest/simplest first)
% ============================================================

girder_type(voided_precast).
girder_type(next_beams).
girder_type(steel_beams).

% ============================================================
% Girder Lengths  (m) — available stock lengths per girder type
% ============================================================

girder_lengths(voided_precast,  8).
girder_lengths(voided_precast, 10).
girder_lengths(voided_precast, 12).
girder_lengths(voided_precast, 14).
girder_lengths(next_beams,      9).
girder_lengths(next_beams,     11).
girder_lengths(next_beams,     13).
girder_lengths(next_beams,     15).
girder_lengths(next_beams,     17).
girder_lengths(next_beams,     19).
% steel_beams is custom-fabricated to length rather than a fixed precast
% stock item, so it's available in 1 m increments over its practical range
% (unlike voided_precast/next_beams, which come in discrete stock lengths).
girder_lengths(steel_beams, L) :- between(20, 70, L).

% ============================================================
% Girder Section Properties
% girder_props(Type, depth(m), width(m))
%   width: tributary deck width per girder, used for girder count and
%   dead-load distribution. Unit costs live in price_list (girder_cost_per_m/2
%   for precast types; steel_beams is priced by weight/volume, see price_list).
% ============================================================

girder_props(voided_precast, depth(0.51), width(1.2)).
girder_props(next_beams,     depth(1.0),  width(2.5)).
girder_props(steel_beams,    depth(1.0),  width(2.5)). % 2 beams + deck

% ============================================================
% Pile Diameter Catalogue  (m)
% ============================================================

dias([0.3, 0.4, 0.5, 0.6]).

% ============================================================
% Superstructure Dead Weight
% girder_unit_weight(Type, kN/m) -- self-weight per girder, per linear metre
% ============================================================

% voided_precast and next_beams are given as flat composite (beam+deck)
% unit weights.
girder_unit_weight(voided_precast, 11.4).
girder_unit_weight(next_beams,     23.4).

% steel_beams is built up from an assumed I-section (web + 2 flanges of
% equal area to the web) plus its tributary concrete deck slab strip:
%   steel area  = 3 x web_thickness x depth   (web + top flange + bottom flange)
%   slab strip  = slab_thickness x tributary width (girder_props' width/1)
steel_web_thickness(0.016).   % m (16 mm)
steel_density(79).            % kN/m3
slab_thickness(0.2).          % m (200 mm)
concrete_density(24).         % kN/m3 (reinforced concrete)

girder_unit_weight(steel_beams, UnitWeight) :-
    girder_props(steel_beams, depth(H), width(TribWidth)),
    steel_web_thickness(Tw),
    steel_density(Gs),
    slab_thickness(Ts),
    concrete_density(Gc),
    SteelArea is 3 * Tw * H,
    SteelWeight is SteelArea * Gs,
    SlabWeight is Ts * TribWidth * Gc,
    UnitWeight is SteelWeight + SlabWeight.
