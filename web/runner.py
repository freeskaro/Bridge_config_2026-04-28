"""
Validates web-form input and runs the Prolog solver.

Each submission gets a fresh temp directory containing symlinks to the
(unmodified) solver source files plus a freshly generated site_facts.pl
holding that request's inputs, and is solved in its own swipl subprocess.
That keeps concurrent public submissions fully isolated from each other
and from the repo's own site_facts.pl -- nothing here ever mutates repo
files or shares Prolog process state across requests.
"""
import os
import re
import shutil
import subprocess
import tempfile

WEB_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(WEB_DIR)
SITE_FACTS_PATH = os.path.join(REPO_DIR, 'site_facts.pl')
QUERY_TEMPLATE = os.path.join(WEB_DIR, 'query_template.pl')

# Files consulted transitively by prolog_bridge_config.pl (see README's
# "Consult chain"), excluding site_facts.pl which is generated per request.
SOLVER_FILES = [
    'prolog_bridge_config.pl',
    'abut_soil_config_8.pl',
    'Abut_config_facts.pl',
    'abut_pile_fallback.pl',
    'abut_print.pl',
    'abut_tree_gravity.pl',
    'Abut_tree_footing_def.pl',
    'CFEM_4th_prolog_qu.pl',
    'bridge_facts.pl',
    'dead_load.pl',
    'Live_load.pl',
    'price_list.pl',
]

# Soil (type, density) combinations offered in the form, restricted to
# ones with friction_angle/3, elastic_modulus/3 AND soil_class_map/3
# entries (see Abut_config_facts.pl / site_facts.pl) so every combination
# a user can pick is fully supported by the solver end to end. sand and
# silt are defined for friction_angle/elastic_modulus but have no
# soil_class_map entry (used for sheet-pile embedment sizing), so they're
# left out here rather than risk a partially-supported soil type on a
# public form.
SOIL_OPTIONS = {
    'gravel': ['loose', 'medium', 'dense'],
    'rock': ['sound'],
}

MAX_LAYERS = 8
ELEV_LO, ELEV_HI = -500.0, 9000.0
SUBPROCESS_TIMEOUT = 40  # hard backstop (SIGKILL); the Prolog script's own internal
                          # call_with_time_limit is 30s but is not fully reliable as a
                          # backstop on its own, so this is the real guarantee


class ValidationError(Exception):
    pass


def _to_float(raw, field_name, lo=ELEV_LO, hi=ELEV_HI):
    try:
        val = float(raw)
    except (TypeError, ValueError):
        raise ValidationError(f"{field_name} must be a number.")
    if not (lo <= val <= hi):
        raise ValidationError(f"{field_name} must be between {lo} and {hi}.")
    return val


def parse_and_validate(form):
    """Extract and validate all fields from a Flask request.form. Raises
    ValidationError with a user-facing message on any problem."""
    approach_elev = _to_float(form.get('approach_elevation'), 'Approach elevation')
    bottom_elev = _to_float(form.get('bottom_elevation'), 'River bed / obstacle elevation')
    dhwl = _to_float(form.get('design_high_water_level'), 'Design high water level')
    hyd_opening = _to_float(form.get('hydraulic_opening'), 'Hydraulic opening', 0.1, 2000)

    if not (bottom_elev < approach_elev):
        raise ValidationError(
            'River bed / obstacle elevation must be lower than approach elevation.'
        )

    types = form.getlist('layer_type[]')
    densities = form.getlist('layer_density[]')
    elevs = form.getlist('layer_elevation[]')

    if not types:
        raise ValidationError('At least one soil layer is required.')
    if len(types) > MAX_LAYERS:
        raise ValidationError(f'No more than {MAX_LAYERS} soil layers are supported.')
    if not (len(types) == len(densities) == len(elevs)):
        raise ValidationError('Soil layer fields are inconsistent.')

    layers = []
    prev_elev = None
    for i, (t, d, e) in enumerate(zip(types, densities, elevs), start=1):
        if t not in SOIL_OPTIONS:
            raise ValidationError(f'Layer {i}: unsupported soil type.')
        if d not in SOIL_OPTIONS[t]:
            raise ValidationError(f'Layer {i}: unsupported density for {t}.')
        elev = _to_float(e, f'Layer {i} top elevation')
        if prev_elev is not None and elev >= prev_elev:
            raise ValidationError(
                'Soil layer top elevations must strictly decrease from top to bottom.'
            )
        prev_elev = elev
        layers.append((t, d, elev))

    if layers[0][2] != approach_elev:
        raise ValidationError(
            'The top soil layer must start at the approach elevation, since that is '
            'where the ground surface meets the abutment.'
        )

    if layers[-1][2] >= bottom_elev:
        raise ValidationError(
            'The deepest soil layer must start at or below the river bed / obstacle elevation.'
        )

    return {
        'approach_elevation': approach_elev,
        'bottom_elevation': bottom_elev,
        'design_high_water_level': dhwl,
        'hydraulic_opening': hyd_opening,
        'layers': layers,
    }


def _fmt(x):
    return f'{x:.3f}'  # Prolog float syntax always needs a decimal point


_OVERRIDDEN_PREDICATES = [
    'soil_log1', 'bottom', 'hydraulic_opening', 'design_high_water_level', 'approach_elevation',
]
# Matches a full fact clause line for the predicate, including any trailing
# same-line comment (site_facts.pl documents several of these facts with a
# "% ..." comment after the closing "."), so the original clause is fully
# removed rather than left to coexist -- as a second clause -- alongside the
# generated one. Two clauses for the same 0-ary-argument fact would make it
# backtrackable, and since these facts are read repeatedly throughout the
# solver's search, even one duplicated fact multiplies the entire search
# space rather than just adding one extra branch.
_FACT_PATTERNS = [rf'^{pred}\(.*\)\.[^\n]*\n?' for pred in _OVERRIDDEN_PREDICATES]


def build_site_facts(base_site_facts_text, data):
    """Start from the repo's own site_facts.pl -- so wall-type rules, pile
    parameters, unit weights, scour settings etc. always match whatever
    the repo currently defines -- and replace just the handful of facts
    the web form collects."""
    text = base_site_facts_text
    for pattern in _FACT_PATTERNS:
        text = re.sub(pattern, '', text, flags=re.MULTILINE)

    lines = ['% --- generated per-request facts (web form submission) ---']
    for t, d, e in data['layers']:
        lines.append(f'soil_log1({t}, {d}, {_fmt(e)}).')
    lines.append(f"bottom({_fmt(data['bottom_elevation'])}).")
    lines.append(f"hydraulic_opening({_fmt(data['hydraulic_opening'])}).")
    lines.append(f"design_high_water_level({_fmt(data['design_high_water_level'])}).")
    lines.append(f"approach_elevation({_fmt(data['approach_elevation'])}).")
    lines.append('% --- end generated facts ---\n')

    return '\n'.join(lines) + '\n' + text


def run_solver(data):
    """Build an isolated temp working directory for this request, run the
    solver in a fresh swipl subprocess, and return (ok, report_text)."""
    with open(SITE_FACTS_PATH) as f:
        base_text = f.read()
    site_facts_text = build_site_facts(base_text, data)

    tmpdir = tempfile.mkdtemp(prefix='bridge_config_')
    try:
        for fname in SOLVER_FILES:
            os.symlink(os.path.join(REPO_DIR, fname), os.path.join(tmpdir, fname))
        os.symlink(QUERY_TEMPLATE, os.path.join(tmpdir, 'query_template.pl'))
        with open(os.path.join(tmpdir, 'site_facts.pl'), 'w') as f:
            f.write(site_facts_text)

        try:
            proc = subprocess.run(
                ['swipl', '-q', 'query_template.pl'],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                timeout=SUBPROCESS_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            return False, (
                'The solver did not respond within the time limit. Try fewer '
                'soil layers or a narrower elevation range.'
            )

        output = proc.stdout
        if proc.returncode != 0:
            output += '\n\n--- solver errors ---\n' + proc.stderr
        return proc.returncode == 0, output
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
