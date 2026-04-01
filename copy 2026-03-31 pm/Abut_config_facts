% abut_config_facts.pl
%
% Shared geotechnical facts used across the abutment design modules.
%
% Sources:
%   - friction angles  : CFEM 4th ed. / standard references
%   - elastic moduli   : approximate values (verify against site data)
%
% NOTE: friction_angle for rock/sound is used for base sliding only;
%       review against site-specific interface testing before use.


% ============================================================
% Element Type Mapping
% ============================================================

% elem_type(+GeomType, -StructuralElem)
elem_type(slope,    embankment).   % was misspelled "embankement"
elem_type(confined, retainment).
elem_type(vertical, rock_face).


% ============================================================
% Friction Angles  (degrees)
% ============================================================

% friction_angle(+SoilType, +Density, -PhiDeg)
friction_angle(rock,          sound,  50).  % sliding interface only — verify
friction_angle(gravel,        dense,  36).
friction_angle(gravel,        medium, 32).
friction_angle(gravel,        loose,  30).
friction_angle(sand,          dense,  36).
friction_angle(sand,          medium, 32).
friction_angle(sand,          loose,  30).
friction_angle(clay,          stiff,  30).
friction_angle(clay,          firm,   25).
friction_angle(clay,          soft,   15).
friction_angle(silt,          _,      30).
friction_angle(organic_soils, _,      20).


% ============================================================
% Elastic Moduli  (kPa)
% ============================================================

% elastic_modulus(+SoilType, +Density, -E_MPa)
%
%       to stay consistent with settlement_strip/5 and design_wall/9.

% Rock elastic modulus (kPa)
elastic_modulus(rock, sound,        30000000).   % ~30,000 MPa (granite/basalt typical)
elastic_modulus(rock, hard,          3000000).   % ~3,000 MPa (sandstone/limestone typical)
elastic_modulus(rock, soft,           500000).   % ~500 MPa (chalk/mudstone typical)
% Gravel
elastic_modulus(gravel, dense,        150000).   % ~150 MPa
elastic_modulus(gravel, medium,       100000).   % ~100 MPa
elastic_modulus(gravel, loose,         50000).   % ~50 MPa
% Sand
elastic_modulus(sand, dense,          100000).   % ~100 MPa (very dense sand/gravel upper)
elastic_modulus(sand, medium,          25000).   % ~25 MPa
elastic_modulus(sand, loose,           20000).   % ~20 MPa
% Silty sand
elastic_modulus(silty_sand, dense,     50000).   % ~50 MPa
elastic_modulus(silty_sand, loose,     15000).   % ~15 MPa
% Clay (drained E')
elastic_modulus(clay, very_stiff,     150000).   % ~150 MPa
elastic_modulus(clay, stiff,           50000).   % ~50 MPa
elastic_modulus(clay, medium,          20000).   % ~20 MPa
elastic_modulus(clay, soft,             5000).   % ~5 MPa
elastic_modulus(clay, very_soft,        1000).   % ~1 MPa
% Silt
elastic_modulus(silt, stiff,           40000).   % ~40 MPa
elastic_modulus(silt, soft,             5000).   % ~5 MPa
% Organic soils / peat
elastic_modulus(organic_soils, _,        500).   % ~0.5 MPa