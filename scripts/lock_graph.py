"""Constrained v4 local locator retargeting, checked against generated pinned CLI locks.

This does not resolve dependencies. It preserves the compiler-generated pinned
graph and only retargets local locators and their dependency-only manifest digest.
The serializer is accepted only when every generated local node first matches it.
"""
from pathlib import Path
import hashlib
import json
import re
import tomllib


def require(ok, message):
    if not ok:
        raise ValueError(message)


def quoted(s):
    return json.dumps(s, ensure_ascii=False)


def digest(manifest):
    data = tomllib.loads(manifest)
    deps = dict(data.get('dependencies', {}))
    # Legacy Sui manifests with an explicit Sui override disable implicit deps.
    explicit = 'Sui' in deps
    implicit = data['package'].get('implicit-dependencies', not explicit)
    if implicit and data['package']['name'] not in {'std', 'sui'}:
        require('std' not in deps and 'sui' not in deps, 'Implicit dependency alias collision')
        deps.update(std={'system': 'std', 'override': True}, sui={'system': 'sui', 'override': True})
    require(not data.get('dep-replacements'), 'Environment replacement outside frozen format')
    entries = []
    for alias, dep in sorted(deps.items()):
        require(not (set(dep) - {'local', 'git', 'rev', 'subdir', 'system', 'override'}), 'Unsupported dependency fields: ' + str(dep))
        if 'local' in dep:
            body = 'Local = { local = ' + quoted(dep['local']) + ' }'
        elif 'git' in dep:
            body = 'Git = { git = ' + quoted(dep['git']) + ', rev = ' + quoted(dep['rev']) + ', subdir = ' + quoted(dep.get('subdir', '')) + ' }'
        elif 'system' in dep:
            body = 'System = { system = ' + quoted(dep['system']) + ' }'
        else:
            raise ValueError('Unsupported dependency')
        entries.append(alias + ' = { ' + body + ', override = ' + str(dep.get('override', False)).lower() + ', use-environment = "mainnet" }')
    preimage = 'deps = ' + ('{ ' + ', '.join(entries) + ' }' if entries else '{}') + '\n'
    return hashlib.sha256(preimage.encode()).hexdigest().upper(), preimage


def replace_locators(text, mapping):
    def replace(match):
        old = match.group(1)
        require(old in mapping, 'Unknown local locator: ' + old)
        return 'local = ' + quoted(str(mapping[old]))
    return re.sub(r'local\s*=\s*"([^"]+)"', replace, text)


def check_lock(root, roots):
    lock = tomllib.loads((root / 'Move.lock').read_text())
    require(lock['move']['version'] == 4, 'Expected generated v4 lock')
    nodes = lock['pinned']['mainnet']
    result = []
    for name, node in nodes.items():
        source = node['source']
        p = root if source.get('root') else Path(source['local']) if 'local' in source else None
        if p is None:
            continue
        require(str(p) in roots, 'Unpinned local node ' + str(p))
        data = tomllib.loads((p / 'Move.toml').read_text())
        computed, preimage = digest((p / 'Move.toml').read_text())
        require(computed == node['manifest_digest'], 'Generated manifest digest mismatch: ' + str(root) + ':' + name)
        expected = data.get('dependencies', {})
        # Every manifest local edge resolves to the exact generated local lock node.
        for alias, dep in expected.items():
            if 'local' not in dep:
                continue
            target = (p / dep['local']).resolve()
            target_node = nodes[node['deps'][alias]]
            require(target_node['source'].get('local') == str(target), 'Local edge mismatch: ' + str(p) + ':' + alias)
            require(tomllib.loads((target / 'Move.toml').read_text())['package']['name'] == roots[str(target)], 'Local package identity mismatch: ' + str(target))
        result.append({'root': str(root), 'node': name, 'manifest': str(p / 'Move.toml'), 'digest': computed, 'preimage': preimage})
    return result


def retarget_lock(text, root, manifests, mapping):
    # Validate current digests before touching source locators. Recompute digests
    # from each retargeted manifest and leave all git pins and graph aliases intact.
    def block(match):
        header, body = match.group(1), match.group(2)
        node = tomllib.loads(header + body)['pinned']['mainnet']
        name, data = next(iter(node.items()))
        source = data['source']
        p = str(root) if source.get('root') else source.get('local')
        if p is None:
            return header + body
        before = manifests[p]
        require(digest(before)[0] == data['manifest_digest'], 'Retarget source digest mismatch')
        after = replace_locators(before, mapping)
        updated = digest(after)[0]
        body = body.replace('manifest_digest = "' + data['manifest_digest'] + '"', 'manifest_digest = "' + updated + '"')
        if 'local' in source:
            body = replace_locators(body, mapping)
        return header + body
    return re.sub(r'(\[pinned\.mainnet\.[^\]]+\]\n)(.*?)(?=\n\[|\Z)', block, text, flags=re.S)
