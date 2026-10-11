#!/usr/bin/env python3
"""Replay pinned Maker source checks locally; writes only fresh repository evidence."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PIN = '1d7baa7c7314113671415acfa20279b1eedb6ae6d04f286988a00da285e769c3'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_config(config, combined):
    roots = config['graph_roots']
    for name, path in roots.items():
        require(re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*', name) is not None, 'Unsafe root/command label')
        require(Path(path).is_absolute() and Path(path).is_dir(), 'Invalid read-only graph root: ' + name)
    required = {'SoulidityMakerTerms', 'SoulidityMakerAdmission', 'MakerDirectConsumer'}
    require(set(config['maker_builds']) == required, 'Required Maker builds omitted/duplicated')
    require(set(config['combined_builds']) == {'SoulidityApplication', 'soulidity_v1', 'SoulidityCustody', 'SoulidityNative'}, 'Required combined builds omitted/duplicated')
    require(len(config['maker_builds']) == 3 and len(config['combined_builds']) == 4, 'Duplicate build roots')
    require(config['focused_test'] == {'root': 'MakerDirectConsumer', 'count': 10}, 'Required focused behavior controls omitted')
    refusals = config['negative_builds']
    require(len(refusals) == 17 and len({r['root'] for r in refusals}) == 17, 'Required 17 distinct refusals omitted')
    for row in refusals:
        require(row['root'] in roots and row['root'].startswith('Refuse'), 'Invalid refusal root')
        require(re.fullmatch(r'E[A-Z]*[0-9]+', row['primary_code']) is not None, 'Invalid expected diagnostic')
        expected_source = Path(roots[row['root']]) / 'sources/refusal.move'
        require(row['source_file'] == str(expected_source), 'Refusal must identify its exact source')
    require(all(name in roots for name in required | set(config['combined_builds'])), 'Required graph root missing')
    require(set(config['vendor_roots']) == {'VendorSui', 'VendorStdlib', 'VendorWalrus', 'VendorWal'}, 'Exact vendor closure missing')
    require(all(name in roots for name in config['vendor_roots']), 'Vendor graph roots missing')
    for name in required | set(config['combined_builds']):
        evidence = config['build_evidence'][name]
        for kind in ['dump', 'modules']:
            path = Path(evidence[kind])
            require(path.is_file() and not path.is_symlink(), 'Build evidence must be a frozen regular file')
            require(sha(path) == evidence[kind + '_sha256'], 'Build evidence differs from reviewed digest')
        require(bool(json.loads(Path(evidence['modules']).read_text())), 'Empty module inventory cannot prove compilation')


def snapshot(roots):
    result = []
    for name, value in sorted(roots.items()):
        root = Path(value)
        paths = [root / 'Move.toml']
        for optional in ['Move.lock', 'Published.toml']:
            if (root / optional).exists():
                paths.append(root / optional)
        for kind in ['sources', 'tests']:
            paths += sorted((root / kind).rglob('*.move'))
        for path in paths:
            result.append({'root': name, 'path': str(path),
                           'writer': str(path.resolve()), 'sha256': sha(path)})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--combined', action='store_true', help='Also verify actual Application/Core/Custody/Native and original Core tests')
    args = parser.parse_args()
    config_path = ROOT / 'evidence/maker-leaf-extraction/verification-config.json'
    config = json.loads(config_path.read_text())
    validate_config(config, args.combined)
    tool = Path(config['tool'])
    require(sha(tool) == PIN, 'Pinned Sui identity changed')
    before = snapshot(config['graph_roots'])
    require(before == config['frozen_inputs'], 'Current graph differs from reviewed import')
    control_paths = [config_path, Path(__file__), tool]
    for evidence in config['build_evidence'].values():
        control_paths += [Path(evidence['dump']), Path(evidence['modules'])]
    controls = {str(path): sha(path) for path in control_paths}

    def controls_unchanged():
        return all(Path(path).is_file() and sha(Path(path)) == digest for path, digest in controls.items())

    output = ROOT / 'evidence/maker-leaf-extraction/runs' / str(uuid.uuid4())
    require(output.resolve().is_relative_to(ROOT.resolve()), 'Evidence output escapes Maker repository')
    output.mkdir(parents=True, exist_ok=False)
    write(output / 'inputs-before.json', before)
    write(output / 'control-inputs.json', controls)
    results = []

    def execute(label, root, test=False, expected=None, refusal=None):
        install = output / ('scratch-' + label)
        command = [str(tool), 'move', 'test' if test else 'build', '--path', str(root), '--install-dir', str(install)]
        if not test:
            command += ['--dump-bytecode-as-base64', '--with-unpublished-dependencies', '--no-tree-shaking']
        process = subprocess.run(command, capture_output=True)
        stdout, stderr = output / (label + '.stdout'), output / (label + '.stderr')
        stdout.write_bytes(process.stdout)
        stderr.write_bytes(process.stderr)
        text = (process.stdout + process.stderr).decode(errors='replace')
        text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text)
        row = {'label': label, 'command': command, 'exit': process.returncode,
               'stdout': str(stdout), 'stdout_sha256': sha(stdout),
               'stderr': str(stderr), 'stderr_sha256': sha(stderr),
               'gas_limit_override': None, 'package_size_override': None,
               'input_unchanged': snapshot(config['graph_roots']) == before,
               'control_inputs_unchanged': controls_unchanged()}
        if test:
            match = re.search(r'Total tests:\s*(\d+);\s*passed:\s*(\d+);\s*failed:\s*(\d+)', text)
            row['counts'] = list(map(int, match.groups())) if match else None
            row['passed'] = process.returncode == 0 and row['counts'] == [expected, expected, 0]
        elif refusal:
            diagnostics = list(re.finditer(r'error\[(E[A-Z]*[0-9]+)\]', text))
            codes = [match.group(1) for match in diagnostics]
            primary = text[diagnostics[0].start():diagnostics[1].start() if len(diagnostics) > 1 else len(text)] if diagnostics else ''
            locations = re.findall(r'(?:┌─|-->)\s+([^\n]+)', primary)
            locations = [re.sub(r':\d+:\d+\s*$', '', value.strip()) for value in locations]
            # Sui prints paths relative to the --path package; the exact source
            # identity remains fixed in config/source snapshots and this argv.
            expected_locations = {refusal['source_file'], './sources/refusal.move', 'sources/refusal.move'}
            row['diagnostic_codes'] = codes
            row['primary_source_locations'] = locations
            row['passed'] = process.returncode != 0 and bool(codes) and codes[0] == refusal['primary_code'] and any(value in expected_locations for value in locations)
        else:
            inventory = [{'path': str(p.relative_to(install)), 'sha256': sha(p), 'size': p.stat().st_size}
                         for p in sorted(install.rglob('*.mv'))]
            bytes_root = output / 'module-bytes'
            bytes_root.mkdir(exist_ok=True)
            for path in sorted(install.rglob('*.mv')):
                target = bytes_root / (sha(path) + '.mv')
                if not target.exists():
                    target.write_bytes(path.read_bytes())
            write(output / (label + '.modules.json'), inventory)
            expected_inventory = json.loads(Path(expected['modules']).read_text())
            expected_inventory = [{k: r[k] for k in ['path', 'sha256', 'size']} for r in expected_inventory]
            row['candidate_module_bytes_equal'] = inventory == expected_inventory
            row['candidate_raw_dump_equal'] = process.stdout == Path(expected['dump']).read_bytes()
            row['modules'] = len(inventory)
            row['passed'] = process.returncode == 0 and row['candidate_module_bytes_equal'] and row['candidate_raw_dump_equal']
        results.append(row)
        write(output / 'results.json', results)
        print(json.dumps({k: row[k] for k in ['label', 'exit', 'passed', 'input_unchanged']}), flush=True)
        if install.exists():
            # Only this invocation's private scratch, after retaining module bytes/logs.
            shutil.rmtree(install)
        require(row['passed'] and row['input_unchanged'] and row['control_inputs_unchanged'], 'Verification failed: ' + label)

    names = list(config['maker_builds'])
    if args.combined:
        names += list(config['combined_builds'])
    for name in names:
        execute(name, Path(config['graph_roots'][name]), expected=config['build_evidence'][name])
    focus = config['focused_test']
    execute('focused-runtime', Path(config['graph_roots'][focus['root']]), test=True, expected=focus['count'])
    for refusal in config['negative_builds']:
        execute(refusal['root'], Path(config['graph_roots'][refusal['root']]), refusal=refusal)
    if args.combined:
        execute('original-Core', Path(config['graph_roots']['soulidity_v1']), test=True, expected=1038)
    after = snapshot(config['graph_roots'])
    write(output / 'inputs-after.json', after)
    passed = before == after and controls_unchanged() and bool(results) and all(r['passed'] and r['input_unchanged'] and r['control_inputs_unchanged'] for r in results)
    write(output / 'summary.json', {'status': 'PASS scoped actual unpublished source checks' if passed else 'FAIL',
          'config': str(config_path), 'config_sha256': sha(config_path),
          'tool_sha256': PIN, 'verifier_sha256': sha(Path(__file__)),
          'input_files': len(before), 'inputs_unchanged': before == after,
          'control_inputs_unchanged': controls_unchanged(),
          'combined': args.combined, 'results': results, 'rpc_calls': 0,
          'signed_transactions': 0, 'published_compatibility_proven': False,
          'full_Gate0_complete': False, 'full_product_acceptance': False})
    require(passed, 'Final source/control/effect checks failed')
    print('Evidence: ' + str(output), flush=True)


if __name__ == '__main__':
    main()
