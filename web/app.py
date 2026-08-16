"""
Public web front-end for the bridge abutment configuration/cost solver.

Served behind nginx at the /bridge-config/ path prefix (nginx strips the
prefix before proxying here, so every route below is written as if the
app were mounted at "/"). Templates use paths with no leading slash
(e.g. action="solve") rather than url_for()/absolute paths, since an
absolute "/solve" would resolve against the site root and miss the
/bridge-config/ prefix in the browser.
"""
from flask import Flask, render_template, request

from runner import SOIL_OPTIONS, MAX_LAYERS, ValidationError, parse_and_validate, run_solver

app = Flask(__name__)


@app.route('/', methods=['GET'])
def index():
    return render_template(
        'form.html', soil_options=SOIL_OPTIONS, max_layers=MAX_LAYERS,
        error=None, form=None, prefill_layers=[],
    )


@app.route('/solve', methods=['POST'])
def solve():
    try:
        data = parse_and_validate(request.form)
    except ValidationError as e:
        prefill_layers = list(zip(
            request.form.getlist('layer_type[]'),
            request.form.getlist('layer_density[]'),
            request.form.getlist('layer_elevation[]'),
        ))
        return render_template(
            'form.html',
            soil_options=SOIL_OPTIONS,
            max_layers=MAX_LAYERS,
            error=str(e),
            form=request.form,
            prefill_layers=prefill_layers,
        ), 400

    ok, report = run_solver(data)
    return render_template('results.html', ok=ok, report=report)


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001, debug=False)
