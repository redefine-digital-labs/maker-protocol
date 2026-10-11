#!/usr/bin/env python3
"""Exercise sealed verifier guards in normal, -O and -OO without calling Sui."""
from pathlib import Path
import copy
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
import tomllib
import lock_graph as graph
import verify_maker_publication as verify

R = Path(__file__).resolve().parents[1]
E = R / 'evidence'


def write(p, d):
    p.write_text(json.dumps(d, indent=2) + '\n')


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def child(output):
    output.mkdir(parents=True)
    config_path = E / 'verification-config.json'
    config = json.loads(config_path.read_text())
    seal = json.loads((E / 'verification-seal.json').read_text())
    rows = []

    def case(name, function, expected_error=None):
        error = None
        try:
            function()
        except Exception as exc:
            error = str(exc)
        passed = error is None if expected_error is None else error is not None and expected_error in error
        rows.append({'case': name, 'passed': passed, 'error': error, 'expected_error': expected_error})
        write(output / 'results.json', rows)
        require(passed, 'Offline control failed: ' + name + ': ' + str(error))

    roots = {p['candidate']: p['package_name'] for p in config['packages']}
    case('valid-sealed-controls-pinned-Python-and-Sui', lambda: verify.load_controls(config_path))
    case('valid-42-generated-lock-roots', lambda: [graph.check_lock(Path(p['candidate']), roots) for p in config['packages']])
    model = next(p for p in config['packages'] if p['label'] == 'soulidity_model')

    def bad_lock(name, pattern, replacement, expected):
        root = output / name
        root.mkdir()
        shutil.copyfile(Path(model['candidate']) / 'Move.toml', root / 'Move.toml')
        text = (Path(model['candidate']) / 'Move.lock').read_text()
        text, n = re.subn(pattern, replacement, text, count=1)
        require(n == 1, 'Fixture did not change intended lock field')
        (root / 'Move.lock').write_text(text)
        case(name, lambda: graph.check_lock(root, {**roots, str(root): model['package_name']}), expected)

    bad_lock('bad-manifest-digest', r'(\[pinned\.mainnet\.SoulidityModel\]\nsource = \{ root = true \}\nuse_environment = "mainnet"\nmanifest_digest = ")[A-F0-9]+', lambda m: m.group(1) + '0' * 64, 'Generated manifest digest mismatch')
    foundation = next(p['candidate'] for p in config['packages'] if p['label'] == 'soulidity_foundation')
    visual = next(p['candidate'] for p in config['packages'] if p['label'] == 'soulidity_visual')
    bad_lock('bad-local-edge', re.escape('local = "' + foundation + '"'), 'local = "' + visual + '"', 'Local edge mismatch')
    case('unknown-local-locator', lambda: graph.replace_locators('A = { local = "/unknown/producer" }', {}), 'Unknown local locator')
    case('unsupported-dependency-fields', lambda: graph.digest('[package]\nname="Bad"\n[dependencies]\nA={local="/a",unexpected=true}\n'), 'Unsupported dependency fields')
    case('retarget-bad-digest', lambda: graph.retarget_lock((output / 'bad-manifest-digest/Move.lock').read_text(), output / 'bad-manifest-digest', {**{p['candidate']: (Path(p['candidate']) / 'Move.toml').read_text() for p in config['packages']}, str(output / 'bad-manifest-digest'): (output / 'bad-manifest-digest/Move.toml').read_text()}, {p['candidate']: p['candidate'] for p in config['packages']}), 'Retarget source digest mismatch')

    def control_case(name, alter_config=None, alter_seal=None):
        folder = output / name
        folder.mkdir()
        cfg = copy.deepcopy(config)
        if alter_config:
            alter_config(cfg)
        write(folder / 'verification-config.json', cfg)
        sealed = copy.deepcopy(seal)
        sealed['config_sha256'] = verify.sha(folder / 'verification-config.json')
        if alter_seal:
            alter_seal(sealed, folder)
        write(folder / 'verification-seal.json', sealed)
        return folder / 'verification-config.json'

    config_bad = control_case('config-seal-tamper')
    config_bad.write_text(config_bad.read_text() + ' ')
    case('config-seal-tamper', lambda: verify.load_controls(config_bad), 'Reviewed config seal mismatch')
    def corrupt_control(sealed, folder):
        p = folder / 'source-control.py'
        p.write_text('# reviewed\n')
        sealed['controls'][str(p)] = verify.sha(p)
        p.write_text('# tampered\n')
    source_bad = control_case('control-source-tamper', alter_seal=corrupt_control)
    case('control-source-tamper', lambda: verify.load_controls(source_bad), 'Reviewed control mismatch')
    python_bad = control_case('wrong-Python-binary', lambda cfg: cfg['python_tool'].update(binary_sha256='0' * 64))
    case('wrong-Python-binary', lambda: verify.load_controls(python_bad), 'Pinned Python binary identity changed')
    version_bad = control_case('wrong-Python-version', lambda cfg: cfg['python_tool'].update(version_info=[3, 11, 0]))
    case('wrong-Python-version', lambda: verify.load_controls(version_bad), 'Pinned Python version mismatch')

    text = 'error[EC05001]: ability\n  ┌─ ./sources/refusal.move:3:1\n  ┌─ ../dependency.move:1:1\n'
    case('right-first-location-valid', lambda: require(verify.refusal_diagnostic(text, 'EC05001', '/fixture/sources/refusal.move')['first_location_is_expected_refusal_source'], 'Expected valid primary location'))
    wrong_first = 'error[EC05001]: ability\n  ┌─ ../dependency.move:1:1\n  ┌─ ./sources/refusal.move:3:1\n'
    case('wrong-first-right-secondary-refused', lambda: require(not verify.refusal_diagnostic(wrong_first, 'EC05001', '/fixture/sources/refusal.move')['first_location_is_expected_refusal_source'], 'Dependency first location must be refused'))
    case('wrong-code-refused', lambda: require(not verify.refusal_diagnostic(text, 'EC04001', '/fixture/sources/refusal.move')['first_location_is_expected_refusal_source'], 'Wrong first code must be refused'))
    ansi = '\x1b[31merror[EC05001]\x1b[0m: ability\n  ┌─ ./sources/refusal.move:3:1\n'
    case('ANSI-primary-location-valid', lambda: require(verify.refusal_diagnostic(ansi, 'EC05001', '/fixture/sources/refusal.move')['first_location_is_expected_refusal_source'], 'ANSI primary must parse'))
    v1 = E / 'replay-runs/1791646134016005000'
    def actual_refusals():
        for row in config['refusals']:
            text = (v1 / ('refuse-' + row['name'] + '.stdout')).read_text() + (v1 / ('refuse-' + row['name'] + '.stderr')).read_text()
            require(verify.refusal_diagnostic(text, row['primary_code'], row['source_file'])['first_location_is_expected_refusal_source'], 'Wrong v1 primary source: ' + row['name'])
            require(verify.sha(row['source_file']) == row['source_sha256'], 'Fixture source SHA changed')
    case('all-16-real-first-locations-and-source-SHAs', actual_refusals)
    def actual_original_pins():
        pins = dict(config['original_inputs'])
        for row in json.loads((E / 'payload-map.json').read_text()):
            for p in [row['logical_actual_path'], row['actual_target']]:
                if p in pins:
                    pins[p] = row['payload_sha256']
        require(pins == config['actual_original_inputs'], 'Actual-original pins must use payload SHA or preserved original SHA')
    case('all-217-installed-original-pins-derived-exactly', actual_original_pins)
    write(output / 'summary.json', {'passed': all(r['passed'] for r in rows), 'cases': rows, 'python_version': sys.version, 'python_binary_sha256': verify.sha(Path(sys.executable).resolve()), 'optimization_level': sys.flags.optimize, 'sui_invocations': 0, 'rpc_calls': 0, 'signatures': 0})
    print(json.dumps({'mode': sys.flags.optimize, 'cases': len(rows), 'passed': True}), flush=True)


if __name__ == '__main__':
    if sys.argv[1:2] == ['--child']:
        child(Path(sys.argv[2]))
    else:
        output = E / 'offline-control-runs' / str(time.time_ns())
        output.mkdir(parents=True)
        rows = []
        for name, flags in [('normal', []), ('O', ['-O']), ('OO', ['-OO'])]:
            cmd = [sys.executable, *flags, str(Path(__file__).resolve()), '--child', str(output / name)]
            p = subprocess.run(cmd, capture_output=True)
            (output / (name + '.stdout')).write_bytes(p.stdout)
            (output / (name + '.stderr')).write_bytes(p.stderr)
            rows.append({'mode': name, 'command': cmd, 'exit': p.returncode, 'summary': str(output / name / 'summary.json')})
            write(output / 'summary.json', {'passed': all(x['exit'] == 0 for x in rows), 'rows': rows, 'sui_invocations': 0})
            print(json.dumps(rows[-1]), flush=True)
        require(all(r['exit'] == 0 for r in rows), 'Offline controls failed; preserve output: ' + str(output))
        print('Evidence: ' + str(output), flush=True)
