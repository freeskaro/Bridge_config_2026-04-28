% price_list
%
% All unit prices and the pricing calculations that consume them.
% Edit this file to update rates, price a new element type, or add a new
% girder/wall/pile product's cost basis. Physical properties (girder
% depth/width, stock lengths, dead weight) stay in bridge_facts -- this
% file is strictly the $ side of the model.
%
% Consulted by prolog_bridge_config; depends on bridge_facts (girder_props,
% steel_web_thickness, slab_thickness) and prolog_bridge_config itself
% (sum_spans/2, n_girders/3) already being loaded by the time price_solution
% is actually called.

% ============================================================
% Girder Unit Rates
% girder_cost_per_m(Type, $/m per girder) -- supply + transport + erection.
% Precast products only (voided_precast, next_beams); steel_beams is priced
% from first principles below (steel mass + deck concrete volume) instead
% of a flat rate.
% ============================================================

girder_cost_per_m(voided_precast, 2000). % ~$1,667/m2 of deck -- kept cheapest of the three per m2, consistent with girder_type/1's "cheapest/simplest first" ordering
girder_cost_per_m(next_beams,     5000).

% ============================================================
% Steel Girder + Deck Cost (weight/volume based -- steel_beams only)
%
% steel_density_kgm3 is a MASS density (kg/m3), distinct from bridge_facts'
% steel_density/1, which is a kN/m3 UNIT WEIGHT used for load calculations
% -- do not conflate the two.
% ============================================================

steel_unit_cost(10).            % $ per kg of structural steel (supply + fabricate + erect)
steel_density_kgm3(7850).       % kg/m3 -- structural steel mass density
deck_concrete_unit_cost(2400).  % $ per m3 of deck concrete (supply + place, incl. reinforcing)

% ============================================================
% Substructure Unit Rates
% substructure_props(ElemType, Description, CostPerMWidth_$)
%   cost is per metre of bridge width (transverse direction)
% ============================================================

substructure_props(pier,          pipe_pile_bent, 20000). % interior piers
substructure_props(spill_through, pile_pipe_bent, 10000). % spill-through abutments

% ============================================================
% Wall Cost Properties
% wall_cost_props(WallType, PricingMethod, UnitRate_$)
%   volume: cost per abutment = H × B × W × Rate   ($/m³)
%   area:   cost per abutment = H × W × Rate        ($/m²)
% ============================================================

wall_cost_props(concrete_gravity, volume, 2000). % incl. ~$500/m³ for reinforcing steel
wall_cost_props(stub_abutment,    volume, 2000). % incl. ~$500/m³ for reinforcing steel
wall_cost_props(timber_crib,      volume, 2000). % MTQ liste de prix — steel + timber
wall_cost_props(mse_wall,         volume, 600).  % $/m³ incl. facing panels, geogrid reinforcement,
                                                  % select granular backfill; calibrated to the prior
                                                  % $2400/m² face-area estimate at a typical B=4m footing
wall_cost_props(gabion_block,     volume, 450).  % $/m³ incl. basket + stone fill; calibrated to the prior
                                                  % $1300/m² face-area estimate at a typical B=3.75m (B/H=0.75)
                                                  % footing for a 5m wall -- the model's own design gives that
                                                  % B/H ratio at H=5m, same calibration approach as mse_wall above
wall_cost_props(sheet_piling,     area,    1100). % $/m² face area (supply + drive)
wall_cost_props(rip_rap,          area,    150). % $/m² plan area (supply + place)

% ============================================================
% Pile Foundation Cost
% ============================================================

pile_cost_per_m(600).   % $ per pile per metre of length (supply + drive)

% Piles driven less than this length before meeting rock don't have enough
% embedded shaft length to develop lateral resistance from soil passive
% pressure alone, and must be socketed into the rock instead. The socket
% itself adds nominal length drilled INTO the rock (rock_socket_length) on
% top of whatever soil embedment exists above it -- this keeps costing
% from collapsing to $0 when rock sits right at the founding elevation.
rock_socket_min_length(5).      % m -- below this, sockets are required
rock_socket_length(3).          % m -- nominal length drilled into rock
rock_socket_cost_multiplier(3). % rock-socketed piles cost 3x pile_cost_per_m

% ============================================================
% Per-Element Cost Calculation
% ============================================================

% price_element(+Elem, +RW, -priced(Elem, Label, Cost))
% Prices a single element from PropElem for BOTH abutments combined.

price_element(Elem, RW, priced(Elem, Label, Cost)) :-
    Elem = elem(piles, RowCounts, _, PileLength, _, _, _), !,
    sum_spans(RowCounts, NPiles),
    pile_cost_per_m(BaseRate),
    rock_socket_min_length(MinLen),
    ( number(PileLength), PileLength < MinLen ->
        rock_socket_cost_multiplier(Mult),
        rock_socket_length(SocketLen),
        Rate is BaseRate * Mult,
        TotalLength is PileLength + SocketLen,
        Cost is 2 * NPiles * TotalLength * Rate,
        format(atom(Label), "piles (~w piles x2 abuts, rock-socketed, L=~1fm+~1fm socket)",
               [NPiles, PileLength, SocketLen])
    ;
        Rate = BaseRate,
        Cost is 2 * NPiles * PileLength * Rate,
        format(atom(Label), "piles (~w piles x2 abuts, L=~1fm)", [NPiles, PileLength])
    ).

price_element(Elem, RW, priced(Elem, Label, Cost)) :-
    Elem = elem(retainment, _, BotElev, _, TopElev, B, concrete_gravity), !,
    wall_cost_props(concrete_gravity, volume, Rate),
    H is TopElev - BotElev,
    ( B > 2.5 ->
        % T-shaped cross-section: footing (1.5 x B) + stem ((H-1.5) x 1.5)
        XSection is 1.5 * B + (H - 1.5) * 1.5,
        format(atom(Label),
               "retainment wall (concrete_gravity cantilever, H=~1f m, B=~1f m)", [H, B])
    ;
        % Rectangular block
        XSection is H * B,
        format(atom(Label),
               "retainment wall (concrete_gravity, H=~1f m, B=~1f m)", [H, B])
    ),
    Cost is 2 * XSection * RW * Rate.

price_element(Elem, RW, priced(Elem, Label, Cost)) :-
    Elem = elem(retainment, _, BotElev, _, TopElev, B, WallType), !,
    wall_cost_props(WallType, Method, Rate),
    H is TopElev - BotElev,
    ( Method == volume ->
        OneSide is H * B * RW * Rate
    ;
        OneSide is H * RW * Rate
    ),
    Cost is 2 * OneSide,
    format(atom(Label), "retainment wall (~w, H=~1f m, B=~1f m)", [WallType, H, B]).

price_element(Elem, RW, priced(Elem, Label, Cost)) :-
    Elem = elem(stub_abutment, _, BotElev, _, TopElev, B, _), !,
    wall_cost_props(stub_abutment, volume, Rate),
    H is TopElev - BotElev,
    Cost is 2 * H * B * RW * Rate,
    format(atom(Label), "stub abutment (H=~1f m, B=~1f m)", [H, B]).

price_element(Elem, RW, priced(Elem, Label, Cost)) :-
    Elem = elem(embankment, _, BotElev, _, TopElev, _, _), !,
    H is TopElev - BotElev,
    Cost is 2 * 30 * RW * H,
    format(atom(Label), "embankment (H=~1f m)", [H]).

price_element(Elem, RW, priced(Elem, Label, Cost)) :-
    Elem = elem(sheet_piling, _, BotElev, _, TopElev, _, _), !,
    wall_cost_props(sheet_piling, area, Rate),
    H is TopElev - BotElev,
    Cost is 2 * H * RW * Rate,
    format(atom(Label), "sheet piling (H=~1f m)", [H]).

price_element(Elem, RW, priced(Elem, Label, Cost)) :-
    Elem = elem(rip_rap, _, _, _, _, Extent, _), !,
    wall_cost_props(rip_rap, area, Rate),
    Cost is 2 * Extent * RW * Rate,
    format(atom(Label), "rip rap (~1f m extent)", [Extent]).

price_element(Elem, _RW, priced(Elem, other, 0)).

% price_elements(+PropElem, +RW, -PricedList)
price_elements([], _, []).
price_elements([E|Es], RW, [PE|PEs]) :-
    price_element(E, RW, PE),
    price_elements(Es, RW, PEs).

% price_pier(+Piers, +RW, -priced(Piers, Label, Cost))
price_pier(Piers, RW, priced(Piers, Label, Cost)) :-
    Piers = piers(NPiers, _, _, _, _),
    substructure_props(pier, _, PierRate),
    Cost is NPiers * PierRate * RW,
    format(atom(Label), "piers (~w x pipe_pile_bent)", [NPiers]).

% girder_cost_items(+GirderType, +RoadwayWidth, +NGirders, +TotalSpanLen, -Items)
%
% steel_beams: priced from first principles rather than a flat $/m rate --
% structural steel by mass (web + 2 flanges cross-section, per
% girder_unit_weight/2's SteelArea) x $/kg, and the deck concrete slab by
% volume (full roadway width, poured once -- not per-girder tributary
% strip) x $/m3. Two line items, so the steel/concrete split is visible.
girder_cost_items(steel_beams, RoadwayWidth, NGirders, TotalSpanLen, [SteelItem, DeckItem]) :-
    !,
    girder_props(steel_beams, depth(H), _),
    steel_web_thickness(Tw),
    SteelArea is 3 * Tw * H,
    SteelVolume is SteelArea * TotalSpanLen * NGirders,
    steel_density_kgm3(RhoSteel),
    SteelMassKg is SteelVolume * RhoSteel,
    steel_unit_cost(SteelRate),
    SteelCost is SteelMassKg * SteelRate,
    format(atom(SLabel), "steel girders (~w, ~0f kg total @ $~w/kg)", [NGirders, SteelMassKg, SteelRate]),
    SteelItem = priced(steel_girders, SLabel, SteelCost),

    slab_thickness(Ts),
    DeckVolume is Ts * RoadwayWidth * TotalSpanLen,
    deck_concrete_unit_cost(ConcRate),
    DeckCost is DeckVolume * ConcRate,
    format(atom(DLabel), "deck concrete (~1f m3 @ $~w/m3)", [DeckVolume, ConcRate]),
    DeckItem = priced(deck_concrete, DLabel, DeckCost).

% voided_precast / next_beams: precast products, priced by a flat
% supply+transport+erection $/m rate per girder (girder_cost_per_m/2 above).
girder_cost_items(GirderType, _RoadwayWidth, NGirders, TotalSpanLen, [GirderItem]) :-
    girder_cost_per_m(GirderType, CpM),
    GirderCost is CpM * TotalSpanLen * NGirders,
    format(atom(GLabel), "girders (~w, ~w/span, ~1f m total)", [GirderType, NGirders, TotalSpanLen]),
    GirderItem = priced(girders, GLabel, GirderCost).

% ============================================================
% Solution Total
% ============================================================

% price_solution(+Sol, -PricedItems, -TotalCost)
% PricedItems is a list of priced(Item, Label, Cost) for every line item.
price_solution(solution(_N, PropElem, _BL, GirderType, SpanLengths, Piers),
               PricedItems, TotalCost) :-
    roadway_width(RW),
    % girder (+ deck, for steel_beams) line item(s)
    n_girders(GirderType, RW, NGirders),
    sum_spans(SpanLengths, TotalSpanLen),
    girder_cost_items(GirderType, RW, NGirders, TotalSpanLen, GirderItems),
    % per-element abutment items
    ( is_list(PropElem) ->
        price_elements(PropElem, RW, ElemItems)
    ;
        ElemItems = []
    ),
    % pier item
    price_pier(Piers, RW, PierItem),
    % assemble
    append(GirderItems, ElemItems, GirderAndElemItems),
    append(GirderAndElemItems, [PierItem], PricedItems),
    sum_priced(PricedItems, TotalCost).

% sum_priced(+PricedItems, -Total)
sum_priced([], 0).
sum_priced([priced(_, _, C) | T], Total) :-
    sum_priced(T, T1),
    Total is T1 + C.

% solution_cost/2 — backward-compatible wrapper
solution_cost(Sol, TotalCost) :-
    price_solution(Sol, _, TotalCost).
