% dead_load
%
% Dead-load reactions at abutments and piers from the superstructure
% self-weight, for use towards computing bearing_x_load.
%
% Each span is treated as an independent simply-supported girder run:
% every support (abutment or pier) under a span's end carries half that
% span's total dead weight. An abutment sits under only one span, so it
% carries half of that span alone. A pier sits between two spans, so it
% carries half of EACH of the two spans framing into it.
%
% Depends on girder_unit_weight/2 and n_girders/3 (bridge_facts /
% prolog_bridge_config), consulted by whichever file loads this one.

% ============================================================
% Abutment Reactions
% ============================================================

% abutment_dead_reaction(+GirderType, +SpanLengths, +RoadwayWidth, -Front, -Back)
% Reaction at each end abutment: half the dead weight of the span framing
% into it (the first span for the front abutment, the last for the back).
abutment_dead_reaction(GirderType, SpanLengths, RoadwayWidth, Front, Back) :-
    girder_unit_weight(GirderType, UnitWeight),
    n_girders(GirderType, RoadwayWidth, NGirders),
    SpanLengths = [FirstSpan|_],
    last(SpanLengths, LastSpan),
    Front is UnitWeight * NGirders * FirstSpan / 2,
    Back is UnitWeight * NGirders * LastSpan / 2.

% abutment_dead_reaction(+Solution, -Front, -Back)
% Convenience form taking a solution(...) term directly.
abutment_dead_reaction(solution(_N, _PropElem, _BL, GirderType, SpanLengths, _Piers), Front, Back) :-
    roadway_width(RW),
    abutment_dead_reaction(GirderType, SpanLengths, RW, Front, Back).

% ============================================================
% Pier Reactions
% ============================================================

% pier_dead_reactions(+GirderType, +SpanLengths, +RoadwayWidth, -PierReactions)
% One reaction per interior pier: half of each of its two adjacent spans.
% Empty list for a single-span bridge (no piers).
pier_dead_reactions(GirderType, SpanLengths, RoadwayWidth, PierReactions) :-
    girder_unit_weight(GirderType, UnitWeight),
    n_girders(GirderType, RoadwayWidth, NGirders),
    pier_dead_reactions_(UnitWeight, NGirders, SpanLengths, PierReactions).

pier_dead_reactions_(_, _, [_], []) :- !.
pier_dead_reactions_(UnitWeight, NGirders, [L1,L2|Rest], [Pier|Piers]) :-
    Pier is UnitWeight * NGirders * (L1+L2) / 2,
    pier_dead_reactions_(UnitWeight, NGirders, [L2|Rest], Piers).

% pier_dead_reactions(+Solution, -PierReactions)
% Convenience form taking a solution(...) term directly.
pier_dead_reactions(solution(_N, _PropElem, _BL, GirderType, SpanLengths, _Piers), PierReactions) :-
    roadway_width(RW),
    pier_dead_reactions(GirderType, SpanLengths, RW, PierReactions).
