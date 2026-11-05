#!/usr/bin/env python3
"""Check CLI output and discovery without contacting a real cluster."""
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
from socketserver import BaseRequestHandler, ThreadingTCPServer
import types
from unittest.mock import patch

import yaml


REPO = Path(__file__).resolve().parents[1]
helper = types.ModuleType('hsctl_kubernetes')
source = (REPO / 'hsctl.d/get.sh').read_text().split("<<'KUBERNETES_PY'\n", 1)[1].split('\nKUBERNETES_PY\n', 1)[0]
exec(compile(source, str(REPO / 'hsctl.d/get.sh'), 'exec'), helper.__dict__)


def executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix='hsctl-discovery-') as temporary:
    root = Path(temporary)
    tools = root / 'bin'
    tools.mkdir()
    for name in ['omnictl', 'infisical']:
        executable(tools / name, '#!/bin/sh\necho "unexpected external call" >&2\nexit 95\n')
    executable(tools / 'tailscale', '''#!/usr/bin/env python3
import json, os, pathlib, sys, time
assert sys.argv[1:] == ["status", "--json"]
if os.environ.get("MOCK_TAILSCALE_HANG"):
    time.sleep(30)
root = pathlib.Path(os.environ["MOCK_ROOT"])
print((root / "tailscale.json").read_text())
''')
    executable(tools / 'kubectl', '''#!/usr/bin/env python3
import json, os, pathlib, sys, yaml
root = pathlib.Path(os.environ["MOCK_ROOT"])
args = sys.argv[1:]
assert args[:2] == ["get", "nodes"] and not any(arg.startswith("--context") for arg in args)
with (root / "calls").open("a") as stream:
    stream.write(json.dumps(args) + "\\n")
if os.environ.get("MOCK_KUBECTL_FAIL"):
    print("cluster unavailable", file=sys.stderr)
    sys.exit(7)
result = json.loads((root / "nodes.json").read_text())
if args[2] not in ["-o"]:
    result = next(node for node in result["items"] if node["metadata"]["name"] == args[2])
print(yaml.safe_dump(result) if args[-1] == "yaml" else json.dumps(result))
''')
    executable(tools / 'yq', '''#!/usr/bin/env python3
import json, os, pathlib, sys, yaml
args = sys.argv[1:]
if os.environ.get("MOCK_YQ_FAIL") and "-o=yaml" in args:
    sys.exit(7)
value = yaml.safe_load(pathlib.Path(args[-1]).read_text() if args[-1] != "." else sys.stdin.read())
print(json.dumps(value) if "-o=json" in args else yaml.safe_dump(value))
''')
    executable(tools / 'topf', '''#!/usr/bin/env python3
import json, os, pathlib, re, sys, yaml
root = pathlib.Path(os.environ["MOCK_ROOT"])
assert pathlib.Path.cwd() == (root / "clusters" / "production").resolve()
assert sys.argv[1] == "--nodes-filter" and sys.argv[3:] == ["nodes", "-o", "yaml"]
with (root / "topf-calls").open("a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ.get("MOCK_TOPF_FAIL"):
    print("Talos API unavailable", file=sys.stderr)
    sys.exit(7)
entries = json.loads((root / "topf-nodes.json").read_text())
print(yaml.safe_dump([entry for entry in entries if re.search(sys.argv[2], entry["node"]["host"])]))
''')
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], MOCK_ROOT=str(root),
                       HSCTL_REPO_ROOT=str(root), HSCTL_ROOT=str(REPO),
                       HSCTL_OIDC_ISSUER_URL='https://issuer.example.test', HSCTL_OIDC_CLIENT_ID='test-client')

    def run(arguments, expected=0, extra=None):
        result = subprocess.run([str(REPO / 'hsctl'), 'get', *arguments], env=dict(environment, **(extra or {})),
                                text=True, capture_output=True, timeout=30)
        assert result.returncode == expected, result.stdout + result.stderr
        return result

    def node(name, ready, control_plane=False, cordoned=False, ip='10.1.245.21'):
        return {'apiVersion': 'v1', 'kind': 'Node', 'metadata': {
            'name': name, 'creationTimestamp': (datetime.now(timezone.utc) - timedelta(days=3)).isoformat(),
            'labels': {'node-role.kubernetes.io/control-plane': '', 'REDACTED/role': 'production-cp-1'} if control_plane else {}},
            'spec': {'unschedulable': cordoned}, 'status': {
                'conditions': [] if ready is None else [{'type': 'Ready', 'status': ready}],
                'addresses': [{'type': 'ExternalIP', 'address': '203.0.113.10'}, {'type': 'InternalIP', 'address': ip}],
                'nodeInfo': {'osImage': 'Talos (v1.14.5)', 'kernelVersion': '6.12.1-talos',
                             'kubeletVersion': 'v1.37.1', 'containerRuntimeVersion': 'containerd://2.1.0'}}}

    nodes = {'apiVersion': 'v1', 'kind': 'List', 'items': [node('talos-aaa-bbb', 'False', True),
             node('talos-ccc-ddd', 'False', cordoned=True, ip='10.1.245.22'),
             node('talos-eee-fff', 'True', ip='10.1.245.23'), node('talos-ggg-hhh', None, ip='10.1.245.24')]}
    (root / 'nodes.json').write_text(json.dumps(nodes))
    (root / 'tailscale.json').write_text(json.dumps({'BackendState': 'Running', 'Peer': None}))
    schematic = '75b960f2' + 'a' * 56
    topf_nodes = [
        {'node': {'host': 'production-cp-3', 'ip': '10.1.245.23'}, 'schematic': schematic,
         'machinestatus': {'stage': 'booting', 'status': {'ready': False, 'unmetConditions': [{'name': 'etcd', 'reason': 'waiting for quorum'},
                                                        {'name': 'kubelet', 'reason': 'not ready'}]}}},
        {'node': {'host': 'production-cp-1', 'ip': '10.1.245.21'}, 'schematic': schematic,
         'machinestatus': {'stage': 'running', 'status': {'ready': True, 'unmetConditions': []}}},
        {'node': {'host': 'production-cp-2', 'ip': '10.1.245.22'}, 'error': 'connection refused'},
        {'node': {'host': 'production-wrk-1', 'ip': '10.1.245.25'}, 'schematic': 'unrelated'},
    ]
    (root / 'topf-nodes.json').write_text(json.dumps(topf_nodes))
    project = root / 'clusters' / 'production'
    project.mkdir(parents=True)
    (project / 'topf.yaml').write_text(yaml.safe_dump({'nodes': [entry['node'] for entry in topf_nodes]}))
    result = run(['nodes'])
    table = result.stdout.splitlines()
    assert table[0].split() == ['NAME', 'STAGE', 'READY', 'TYPE', 'ROLE', 'IP', 'IMAGE', 'SCHEMATIC', 'KERNEL',
                                'KUBELET', 'RUNTIME', 'AGE', 'UNMET', 'CONDITIONS', 'ERROR']
    assert table[1].split()[1:3] == ['running', '✓'] and 'production-cp-1' in table[1]
    assert table[2].split()[1:3] == ['-', '-'] and 'worker' in table[2]
    assert table[3].split()[1:3] == ['booting', '✗']
    assert table[4].split()[1:3] == ['-', '-']
    assert all('Talos (v1.14.5)' in row and 'containerd://2.1.0' in row for row in table[1:])
    assert '203.0.113.10' not in '\n'.join(table)
    assert '75b960f2...' in table[1] and 'connection refused' in table[2], result.stdout + result.stderr
    assert 'etcd: waiting for quorum; kubelet: not ready' in table[3]
    assert 'unrelated' not in '\n'.join(table)
    calls = [json.loads(line) for line in (root / 'topf-calls').read_text().splitlines()]
    assert len(calls) == 1
    assert all(re.fullmatch(calls[0][1], f'production-cp-{index}') for index in range(1, 4))
    assert not re.search(calls[0][1], 'production-wrk-1')
    print('PASS: Stage and readiness come from TOPF even when Kubernetes readiness disagrees')
    print('PASS: TOPF status joins by InternalIP and queries only matching inventory hosts once')
    records = json.loads(run(['nodes', '-o', 'json']).stdout)
    assert yaml.safe_load(run(['nodes', '-o', 'yaml']).stdout) == records
    assert len(records) == len(nodes['items'])
    assert list(records[0]) == ['name', 'stage', 'ready', 'type', 'role', 'ip', 'image', 'schematic', 'kernel',
                                'kubelet', 'runtime', 'age', 'unmet_conditions', 'error']
    assert records[0]['schematic'] == schematic and records[0]['unmet_conditions'] == []
    assert records[0]['stage'] == 'running' and records[0]['ready'] is True
    assert records[2]['stage'] == 'booting' and records[2]['ready'] is False
    assert records[1]['ready'] is None and records[3]['stage'] is None
    assert records[1]['error'] == 'connection refused'
    assert records[2]['unmet_conditions'] == ['etcd: waiting for quorum', 'kubelet: not ready']
    assert records[3]['schematic'] is None and records[3]['unmet_conditions'] is None
    assert json.loads(run(['node', 'talos-aaa-bbb', '-o', 'json']).stdout) == [records[0]]
    assert yaml.safe_load(run(['node', 'talos-aaa-bbb', '-o', 'yaml']).stdout) == [records[0]]
    assert 'talos-aaa-bbb' in run(['node', 'talos-aaa-bbb']).stdout
    print('PASS: Table, JSON and YAML share a concise node schema, including named queries')
    print('PASS: Node queries use the active kubectl context')
    result = run(['nodes', '-o', 'json'], extra={'MOCK_TOPF_FAIL': 'true'})
    assert len(json.loads(result.stdout)) == 4 and 'Talos API unavailable' in result.stderr
    assert all(record['schematic'] is None for record in json.loads(result.stdout))
    assert all(record['ready'] is None and record['stage'] is None for record in json.loads(result.stdout))
    print('PASS: TOPF failures warn on stderr and preserve Kubernetes node output')
    run(['nodes'], expected=7, extra={'MOCK_KUBECTL_FAIL': 'true'})
    print('PASS: kubectl failures keep their exit status')
    run(['nodes', '--cluster', 'production'], expected=1)
    run(['kubeconfig', 'development', '--omni'], expected=1)
    for kind in ['List', 'NodeList']:
        (root / 'nodes.json').write_text(json.dumps(dict(nodes, kind=kind)))
        assert len(run(['nodes']).stdout.splitlines()) == len(nodes['items']) + 1
        (root / 'nodes.json').write_text(json.dumps(dict(nodes, kind=kind, items=[])))
        before = (root / 'topf-calls').read_text()
        assert len(run(['nodes']).stdout.splitlines()) == 1
        assert json.loads(run(['nodes', '-o', 'json']).stdout) == []
        assert yaml.safe_load(run(['nodes', '-o', 'yaml']).stdout) == []
        assert (root / 'topf-calls').read_text() == before
    print('PASS: Node queries accept List and NodeList responses')
    print('PASS: An empty cluster prints only the table header')

    def peer(cluster, online=True):
        return {'Online': online, 'Tags': ['tag:k8s', 'tag:env-' + cluster], 'HostName': 'ingress-' + cluster + '-0'}

    status = {'BackendState': 'Running', 'Self': peer('self-cluster'), 'Peer': {
        'a': peer('development'), 'b': peer('development'), 'c': peer('production', False),
        'd': {'Online': True, 'Tags': ['tag:env-ignore']}, 'e': peer('unknown-to-git'), 'f': peer('bad/name')}}
    with patch.object(helper, 'command_json', return_value=status), patch.object(helper, 'probe_cluster', side_effect=lambda name: {'name': name}) as probe:
        assert helper.discover_clusters() == [{'name': 'development'}, {'name': 'self-cluster'}, {'name': 'unknown-to-git'}]
        assert probe.call_count == 3
    print('PASS: Cluster discovery selects online Tailscale cluster tags')
    with patch.object(helper.subprocess, 'run') as curl:
        curl.return_value = subprocess.CompletedProcess([], 0, '{"gitVersion":"v1.37.1"}\n200')
        assert helper.probe_cluster('development')['k8s_version'] == 'v1.37.1'
        arguments = curl.call_args.args[0]
        assert arguments[-1] == 'https://REDACTED/version'
        assert arguments[arguments.index('--max-time') + 1] == '2'
        assert arguments[arguments.index('--connect-timeout') + 1] == '1'
        assert '--insecure' not in arguments
        for code, reachable in [(401, True), (403, True), (500, False), (503, False)]:
            curl.return_value = subprocess.CompletedProcess([], 0, '\n' + str(code))
            assert bool(helper.probe_cluster('development')) is reachable
        print('PASS: APIs returning 200, 401 or 403 count as reachable')
        curl.return_value = subprocess.CompletedProcess([], 60, '')
        assert helper.probe_cluster('development') is None
        curl.side_effect = subprocess.TimeoutExpired('curl', 3)
        assert helper.probe_cluster('development') is None
    print('PASS: API TLS errors and timeouts exclude the cluster')

    release = threading.Event()

    class StalledAPI(BaseRequestHandler):
        def handle(self):
            release.wait(10)

    real_run = subprocess.run
    with ThreadingTCPServer(('127.0.0.1', 0), StalledAPI) as stalled:
        stalled.daemon_threads = True
        threading.Thread(target=stalled.serve_forever, daemon=True).start()

        def local_probe(arguments, **kwargs):
            arguments = [*arguments[:-1], f'https://127.0.0.1:{stalled.server_address[1]}/version']
            return real_run(arguments, **kwargs)

        started = time.monotonic()
        with patch.object(helper, 'command_json', return_value=status), patch.object(helper.subprocess, 'run', side_effect=local_probe):
            assert helper.discover_clusters() == []
        assert time.monotonic() - started < 3, 'offline API probes must run concurrently and fail fast'
        release.set()
        stalled.shutdown()
    print('PASS: Stalled API probes finish within 3 seconds')
    assert json.loads(run(['clusters', '-o', 'json']).stdout) == []
    started = time.monotonic()
    assert 'timed out' in run(['clusters'], expected=1, extra={'MOCK_TAILSCALE_HANG': 'true'}).stderr
    assert time.monotonic() - started < 4, 'a stalled Tailscale daemon must not hang discovery'
    print('PASS: A stalled Tailscale daemon fails within 4 seconds')
    (root / 'tailscale.json').write_text(json.dumps({'BackendState': 'Stopped'}))
    run(['clusters'], expected=1)
    (root / 'tailscale.json').write_text(json.dumps({'BackendState': 'Running', 'Peer': {}}))

    kubeconfig = root / 'kubeconfig'
    original = {'apiVersion': 'v1', 'kind': 'Config', 'current-context': 'unrelated',
                'contexts': [{'name': 'unrelated', 'context': {'cluster': 'unrelated', 'user': 'unrelated'}}]}
    kubeconfig.write_text(yaml.safe_dump(original))
    run(['kubeconfig', 'development'], expected=1, extra={'KUBECONFIG': str(kubeconfig)})
    assert yaml.safe_load(kubeconfig.read_text()) == original
    print('PASS: Unreachable clusters leave kubeconfig unchanged')
    script = '''source "$HSCTL_ROOT/hsctl.d/_lib.sh"
source "$HSCTL_ROOT/hsctl.d/get.sh"
get_clusters() { echo '[{"name":"development"}]'; }
get_kubeconfig development
'''
    for fail in [True, False]:
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script],
                                env=dict(environment, KUBECONFIG=str(kubeconfig), **({'MOCK_YQ_FAIL': 'true'} if fail else {})),
                                text=True, capture_output=True, timeout=30)
        assert bool(result.returncode) is fail, result.stdout + result.stderr
        if fail:
            assert yaml.safe_load(kubeconfig.read_text()) == original
            print('PASS: A failed kubeconfig merge preserves the previous file')
    merged = yaml.safe_load(kubeconfig.read_text())
    assert merged['current-context'] == 'development' and len(merged['contexts']) == 2
    assert merged['clusters'][0]['cluster'] == {'server': 'https://REDACTED'}
    assert merged['users'][0]['user']['exec']['command'] == 'kubectl'
    assert kubeconfig.stat().st_mode & 0o077 == 0 and not list(root.glob('.hsctl-kubeconfig.*'))
    print('PASS: OIDC kubeconfig keeps other contexts and stays private')

    for cluster in ['production', 'development']:
        project = root / 'clusters' / cluster
        project.mkdir(parents=True, exist_ok=True)
        (project / 'topf.yaml').write_text('clusterName: ' + cluster)
    inventory = REPO / 'infra/ansible/inventory/clusters'
    result = subprocess.run([str(inventory), '--list'], env=environment, text=True, capture_output=True, check=True)
    assert json.loads(result.stdout)['clusters']['hosts'] == ['development', 'production']
    result = subprocess.run([str(inventory), '--host', 'development'], env=environment, text=True, capture_output=True, check=True)
    assert json.loads(result.stdout) == {}
    result = subprocess.run(['ansible-inventory', '-i', str(inventory.parent), '--list'],
                            env=dict(environment, ANSIBLE_LOCAL_TEMP=str(root / 'ansible-temp')), text=True, capture_output=True, check=True)
    assert json.loads(result.stdout)['clusters']['hosts'] == ['development', 'production']
    assert not (REPO / 'infra/ansible/inventory/machines').exists()
    print('PASS: Ansible inventory lists clusters from the checkout')
