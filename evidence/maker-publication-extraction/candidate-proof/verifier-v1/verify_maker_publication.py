#!/usr/bin/env python3
"""Replay frozen Maker publication prerequisite in private staged inputs.

--actual reads installed target paths, verifies their reviewed payload bytes,
then stages identical sources with only local locator/digest retargeting.
Neither mode invokes Sui against actual source or changes its lockfiles.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import time
from pathlib import Path
from lock_graph import check_lock, replace_locators, retarget_lock

PIN = '1d7baa7c7314113671415acfa20279b1eedb6ae6d04f286988a00da285e769c3'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def inventory(roots):
    rows = []
    for label, root in sorted(roots.items()):
        root = Path(root)
        files = [root / 'Move.toml', root / 'Move.lock']
        for optional in ['Move.lock.legacy', 'Published.toml']:
            if (root / optional).exists():
                files.append(root / optional)
        for folder in ['sources', 'tests']:
            files += sorted((root / folder).rglob('*.move'))
        for p in files:
            require(p.is_file(), 'Missing input: ' + str(p))
            rows.append({'root': label, 'relative': str(p.relative_to(root)), 'path': str(p), 'sha256': sha(p)})
    return rows


def file_pins(paths):
    return {str(p): sha(p) for p in paths}


def cache_inventory(path):
    return file_pins(sorted(p for p in Path(path).rglob('*') if p.is_file() and (p.suffix == '.move' or p.name in {'Move.toml', 'Move.lock'})))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=Path(__file__).resolve().parents[1] / 'evidence/verification-config.json')
    parser.add_argument('--actual', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    config_path = args.config.resolve()
    config = json.loads(config_path.read_text())
    seal_path = config_path.with_name('verification-seal.json')
    seal = json.loads(seal_path.read_text())
    require(sha(config_path) == seal['config_sha256'], 'Reviewed config seal mismatch')
    for p, expected in seal['controls'].items():
        require(sha(p) == expected, 'Reviewed control mismatch: ' + p)
    tool = Path(config['tool'])
    require(sha(tool) == PIN, 'Pinned Sui identity changed')
    packages = config['packages']
    require(len(packages) == 42 and len({p['label'] for p in packages}) == 42, 'Required 42 distinct root inputs omitted')
    require(len(config['builds']) == 26 and len(config['refusals']) == 16, 'Required build/refusal scope omitted')
    require(config['tests'] == [{'root': 'foreign_publication_producer', 'count': 22}, {'root': 'MakerDirectConsumer', 'count': 10}, {'root': 'soulidity_v1', 'count': 1038}], 'Required runtime scope changed')
    roots = {p['label']: Path(p['actual'] if args.actual else p['candidate']) for p in packages}
    before = inventory(roots)
    expected = {(r['root'], r['relative']): r['actual_sha256'] if args.actual else r['candidate_sha256'] for r in config['inputs']}
    require({(r['root'], r['relative']): r['sha256'] for r in before} == expected, 'Current inputs differ from reviewed payload')
    controls = file_pins([config_path, seal_path, tool] + [Path(p) for p in seal['controls']])
    cache_before = cache_inventory(config['cache'])
    require(cache_before == config['cache_inputs'], 'Cached compiler inputs changed before replay')
    original_before = file_pins(Path(p) for p in config['original_paths'])
    if not args.actual:
        require(original_before == config['original_inputs'], 'Original production/test/manifest/cache controls changed')
    output = args.output.resolve() if args.output else config_path.parent / 'replay-runs' / str(time.time_ns())
    require(not output.exists(), 'Replay output must be fresh')
    output.mkdir(parents=True)
    write(output / 'inputs-before.json', before)
    write(output / 'controls-before.json', controls)
    write(output / 'cache-before.json', cache_before)
    write(output / 'original-before.json', original_before)
    staged = {p['label']: output / 'staged' / p['label'] for p in packages}
    mapping = {str(roots[p['label']]): str(staged[p['label']]) for p in packages}
    manifests = {str(roots[p['label']]): (roots[p['label']] / 'Move.toml').read_text() for p in packages}
    names = {str(roots[p['label']]): p['package_name'] for p in packages}
    lock_checks = [r for p in packages for r in check_lock(roots[p['label']], names)]
    write(output / 'source-lock-checks.json', lock_checks)
    for p in packages:
        label = p['label']
        source, target = roots[label], staged[label]
        target.mkdir(parents=True)
        for row in before:
            if row['root'] != label:
                continue
            src, dst = Path(row['path']), target / row['relative']
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.name == 'Move.toml':
                dst.write_text(replace_locators(src.read_text(), mapping))
            elif src.name == 'Move.lock':
                dst.write_text(retarget_lock(src.read_text(), source, manifests, mapping))
            else:
                shutil.copyfile(src, dst)
        require(all(sha(target / r['relative']) == r['sha256'] for r in before if r['root'] == label and r['relative'].endswith('.move')), 'Staged source bytes changed')
    stage_before = inventory(staged)
    stage_names = {str(staged[p['label']]): p['package_name'] for p in packages}
    stage_checks = [r for p in packages for r in check_lock(staged[p['label']], stage_names)]
    write(output / 'stage-lock-checks.json', stage_checks)
    write(output / 'staged-inputs-before.json', stage_before)
    results = []

    def unchanged():
        return inventory(roots) == before and inventory(staged) == stage_before and file_pins(Path(p) for p in controls) == controls

    def execute(label, root, *, count=None, refusal=None, evidence=None):
        install = output / 'scratch-build'
        cmd = [str(tool), 'move', 'test' if count else 'build', '--path', str(staged[root]), '--install-dir', str(install)]
        if not count:
            cmd += ['--dump-bytecode-as-base64', '--with-unpublished-dependencies', '--no-tree-shaking']
        start = time.monotonic()
        process = subprocess.run(cmd, capture_output=True)
        stdout, stderr = output / (label + '.stdout'), output / (label + '.stderr')
        stdout.write_bytes(process.stdout)
        stderr.write_bytes(process.stderr)
        text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', (process.stdout + process.stderr).decode(errors='replace'))
        row = {'label': label, 'root': root, 'command': cmd, 'exit': process.returncode, 'duration_seconds': time.monotonic() - start, 'stdout': str(stdout), 'stdout_sha256': sha(stdout), 'stderr': str(stderr), 'stderr_sha256': sha(stderr), 'gas_limit_override': None, 'package_size_override': None}
        if count:
            match = re.search(r'Total tests:\s*(\d+);\s*passed:\s*(\d+);\s*failed:\s*(\d+)', text)
            row['counts'] = list(map(int, match.groups())) if match else None
            row['passed'] = process.returncode == 0 and row['counts'] == [count, count, 0]
        elif refusal:
            diagnostics = list(re.finditer(r'error\[(E[A-Z]*[0-9]+)\]', text))
            codes = [d.group(1) for d in diagnostics]
            primary = text[diagnostics[0].start():diagnostics[1].start() if len(diagnostics) > 1 else len(text)] if diagnostics else ''
            locations = [re.sub(r':\d+:\d+\s*$', '', s.strip()) for s in re.findall(r'(?:┌─|-->)\s+([^\n]+)', primary)]
            row.update(diagnostic_codes=codes, primary_diagnostic=primary, primary_source_locations=locations, refusal_source_sha256=sha(staged[root] / 'sources/refusal.move'))
            row['passed'] = process.returncode != 0 and bool(codes) and codes[0] == refusal['primary_code'] and any(s in {'./sources/refusal.move', 'sources/refusal.move', str(staged[root] / 'sources/refusal.move')} for s in locations) and row['refusal_source_sha256'] == refusal['source_sha256']
        else:
            modules = [{'path': str(p.relative_to(install)), 'sha256': sha(p)} for p in sorted(install.rglob('*.mv'))]
            write(output / (label + '.modules.json'), modules)
            byte_dir = output / 'module-bytes'
            byte_dir.mkdir(exist_ok=True)
            for p in sorted(install.rglob('*.mv')):
                dst = byte_dir / (sha(p) + '.mv')
                if not dst.exists():
                    shutil.copyfile(p, dst)
            row['module_count'] = len(modules)
            row['candidate_module_bytes_equal'] = modules == evidence['modules']
            row['candidate_raw_dump_equal'] = sha(stdout) == evidence['dump_sha256']
            row['passed'] = process.returncode == 0 and bool(modules) and row['candidate_module_bytes_equal'] and row['candidate_raw_dump_equal']
        row['all_staged_source_and_controls_unchanged'] = unchanged()
        results.append(row)
        write(output / 'results.json', results)
        print(json.dumps({k: row[k] for k in ['label', 'exit', 'passed', 'all_staged_source_and_controls_unchanged']}), flush=True)
        if install.exists():
            shutil.rmtree(install)
        require(row['passed'] and row['all_staged_source_and_controls_unchanged'], 'Replay failed: ' + label)

    for row in config['builds']:
        execute('build-' + row['root'], row['root'], evidence=row)
    for row in config['tests']:
        execute('test-' + row['root'], row['root'], count=row['count'])
    for row in config['refusals']:
        execute('refuse-' + row['name'], row['name'], refusal=row)
    cache_after = cache_inventory(config['cache'])
    original_after = file_pins(Path(p) for p in config['original_paths'])
    write(output / 'inputs-after.json', inventory(roots))
    write(output / 'staged-inputs-after.json', inventory(staged))
    write(output / 'cache-after.json', cache_after)
    write(output / 'original-after.json', original_after)
    passed = unchanged() and cache_after == cache_before and original_after == original_before and len(results) == 45 and all(r['passed'] for r in results)
    write(output / 'summary.json', {'status': 'PASS' if passed else 'FAIL', 'scope': 'staged actual-input replay' if args.actual else 'staged frozen candidate replay', 'source_bytes_identical': True, 'only_local_locators_and_generated_dependency_digests_retargeted': True, 'source_path_executed': False, 'config_sha256': sha(config_path), 'seal_sha256': sha(seal_path), 'tool_sha256': PIN, 'input_files': len(before), 'cache_files': len(cache_before), 'inputs_and_controls_unchanged': unchanged(), 'cache_inputs_unchanged': cache_after == cache_before, 'original_inputs_unchanged': original_after == original_before, 'results': results, 'rpc_calls': 0, 'signatures': 0, 'full_manufacturing_complete': False, 'published_compatibility_proven': False})
    require(passed, 'Final input/control check failed')
    print('Evidence: ' + str(output), flush=True)


if __name__ == '__main__':
    main()
