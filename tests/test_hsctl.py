"""Check `hsctl get` output and cluster discovery without contacting a real cluster.

All tests in this module share one mocked cluster (`cluster_env` fixture) and run in
file order: later tests build on kubeconfig/file state left behind by earlier ones,
the same way the original hand-written script did.
"""
from datetime import datetime, timedelta, timezone
import json
import os
import re
import subprocess
import threading
import time
import types
from socketserver import BaseRequestHandler, ThreadingTCPServer
from unittest.mock import patch

import pytest
import yaml

from conftest import REPO

HSCTL = REPO / "hsctl"


def node(name, ready, control_plane=False, cordoned=False, ip="10.1.245.21"):
    return {"apiVersion": "v1", "kind": "Node", "metadata": {
        "name": name, "creationTimestamp": (datetime.now(timezone.utc) - timedelta(days=3)).isoformat(),
        "labels": {"node-role.kubernetes.io/control-plane": "", "REDACTED/role": "production-cp-1"} if control_plane else {}},
        "spec": {"unschedulable": cordoned}, "status": {
            "conditions": [] if ready is None else [{"type": "Ready", "status": ready}],
            "addresses": [{"type": "ExternalIP", "address": "203.0.113.10"}, {"type": "InternalIP", "address": ip}],
            "nodeInfo": {"osImage": "Talos (v1.14.5)", "kernelVersion": "6.12.1-talos",
                         "kubeletVersion": "v1.37.1", "containerRuntimeVersion": "containerd://2.1.0"}}}


NODES = {"apiVersion": "v1", "kind": "List", "items": [
    node("talos-aaa-bbb", "False", control_plane=True),
    node("talos-ccc-ddd", "False", cordoned=True, ip="10.1.245.22"),
    node("talos-eee-fff", "True", ip="10.1.245.23"),
    node("talos-ggg-hhh", None, ip="10.1.245.24"),
]}

SCHEMATIC = "75b960f2" + "a" * 56

TOPF_NODES = [
    {"node": {"host": "production-cp-3", "ip": "10.1.245.23"}, "schematic": SCHEMATIC,
     "machinestatus": {"stage": "booting", "status": {"ready": False, "unmetConditions": [
         {"name": "etcd", "reason": "waiting for quorum"}, {"name": "kubelet", "reason": "not ready"}]}}},
    {"node": {"host": "production-cp-1", "ip": "10.1.245.21"}, "schematic": SCHEMATIC,
     "machinestatus": {"stage": "running", "status": {"ready": True, "unmetConditions": []}}},
    {"node": {"host": "production-cp-2", "ip": "10.1.245.22"}, "error": "connection refused"},
    {"node": {"host": "production-wrk-1", "ip": "10.1.245.25"}, "schematic": "unrelated"},
]


@pytest.fixture(scope="module")
def helper():
    """`hsctl.d/get.sh`'s embedded Python heredoc, loaded as a module for unit-level checks."""
    module = types.ModuleType("hsctl_kubernetes")
    source = (REPO / "hsctl.d/get.sh").read_text().split("<<'KUBERNETES_PY'\n", 1)[1].split("\nKUBERNETES_PY\n", 1)[0]
    exec(compile(source, str(REPO / "hsctl.d/get.sh"), "exec"), module.__dict__)
    return module


@pytest.fixture(scope="module")
def cluster_env(tmp_path_factory, executable):
    root = tmp_path_factory.mktemp("hsctl-discovery")
    tools = root / "bin"
    tools.mkdir()
    for name in ["omnictl", "infisical"]:
        executable(tools / name, '#!/bin/sh\necho "unexpected external call" >&2\nexit 95\n')
    executable(tools / "tailscale", '''#!/usr/bin/env python3
import json, os, pathlib, sys, time
assert sys.argv[1:] == ["status", "--json"]
if os.environ.get("MOCK_TAILSCALE_HANG"):
    time.sleep(30)
root = pathlib.Path(os.environ["MOCK_ROOT"])
print((root / "tailscale.json").read_text())
''')
    executable(tools / "kubectl", '''#!/usr/bin/env python3
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
    result = next(n for n in result["items"] if n["metadata"]["name"] == args[2])
print(yaml.safe_dump(result) if args[-1] == "yaml" else json.dumps(result))
''')
    executable(tools / "yq", '''#!/usr/bin/env python3
import json, os, pathlib, sys, yaml
args = sys.argv[1:]
if os.environ.get("MOCK_YQ_FAIL") and "-o=yaml" in args:
    sys.exit(7)
value = yaml.safe_load(pathlib.Path(args[-1]).read_text() if args[-1] != "." else sys.stdin.read())
print(json.dumps(value) if "-o=json" in args else yaml.safe_dump(value))
''')
    for name in ["argocd", "open"]:
        executable(tools / name, "#!/usr/bin/env python3\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n")
    executable(tools / "topf", '''#!/usr/bin/env python3
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
    (root / "nodes.json").write_text(json.dumps(NODES))
    (root / "tailscale.json").write_text(json.dumps({"BackendState": "Running", "Peer": None}))
    (root / "topf-nodes.json").write_text(json.dumps(TOPF_NODES))
    project = root / "clusters" / "production"
    project.mkdir(parents=True)
    (project / "topf.yaml").write_text(yaml.safe_dump({"nodes": [entry["node"] for entry in TOPF_NODES]}))
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"], MOCK_ROOT=str(root),
                       HSCTL_REPO_ROOT=str(root), HSCTL_ROOT=str(REPO),
                       HSCTL_OIDC_ISSUER_URL="https://issuer.example.test", HSCTL_OIDC_CLIENT_ID="test-client")
    return types.SimpleNamespace(root=root, tools=tools, env=environment)


@pytest.fixture(scope="module")
def run_get(cluster_env):
    def invoke(arguments, expected=0, extra=None):
        result = subprocess.run([str(HSCTL), "get", *arguments], env=dict(cluster_env.env, **(extra or {})),
                                text=True, capture_output=True, timeout=30)
        assert result.returncode == expected, result.stdout + result.stderr
        return result
    return invoke


def test_table_shows_topf_stage_even_when_kubernetes_readiness_disagrees(run_get, cluster_env):
    table = run_get(["nodes"]).stdout.splitlines()
    assert table[0].split() == ["NAME", "STAGE", "READY", "TYPE", "ROLE", "IP", "IMAGE", "SCHEMATIC", "KERNEL",
                                "KUBELET", "RUNTIME", "AGE", "UNMET", "CONDITIONS", "ERROR"]
    assert table[1].split()[1:3] == ["running", "✓"] and "production-cp-1" in table[1]
    assert table[2].split()[1:3] == ["-", "-"] and "worker" in table[2]
    assert table[3].split()[1:3] == ["booting", "✗"]
    assert table[4].split()[1:3] == ["-", "-"]
    assert all("Talos (v1.14.5)" in row and "containerd://2.1.0" in row for row in table[1:])
    assert "203.0.113.10" not in "\n".join(table)
    assert "75b960f2..." in table[1] and "connection refused" in table[2]
    assert "etcd: waiting for quorum; kubelet: not ready" in table[3]
    assert "unrelated" not in "\n".join(table)
    calls = [json.loads(line) for line in (cluster_env.root / "topf-calls").read_text().splitlines()]
    assert len(calls) == 1
    assert all(re.fullmatch(calls[0][1], f"production-cp-{index}") for index in range(1, 4))
    assert not re.search(calls[0][1], "production-wrk-1")


def test_table_json_and_yaml_share_one_node_schema(run_get):
    records = json.loads(run_get(["nodes", "-o", "json"]).stdout)
    assert yaml.safe_load(run_get(["nodes", "-o", "yaml"]).stdout) == records
    assert len(records) == len(NODES["items"])
    assert list(records[0]) == ["name", "stage", "ready", "type", "role", "ip", "image", "schematic", "kernel",
                                "kubelet", "runtime", "age", "unmet_conditions", "error"]
    assert records[0]["schematic"] == SCHEMATIC and records[0]["unmet_conditions"] == []
    assert records[0]["stage"] == "running" and records[0]["ready"] is True
    assert records[2]["stage"] == "booting" and records[2]["ready"] is False
    assert records[1]["ready"] is None and records[3]["stage"] is None
    assert records[1]["error"] == "connection refused"
    assert records[2]["unmet_conditions"] == ["etcd: waiting for quorum", "kubelet: not ready"]
    assert records[3]["schematic"] is None and records[3]["unmet_conditions"] is None
    assert json.loads(run_get(["node", "talos-aaa-bbb", "-o", "json"]).stdout) == [records[0]]
    assert yaml.safe_load(run_get(["node", "talos-aaa-bbb", "-o", "yaml"]).stdout) == [records[0]]
    assert "talos-aaa-bbb" in run_get(["node", "talos-aaa-bbb"]).stdout


def test_topf_failure_warns_but_preserves_kubernetes_node_output(run_get):
    result = run_get(["nodes", "-o", "json"], extra={"MOCK_TOPF_FAIL": "true"})
    records = json.loads(result.stdout)
    assert len(records) == 4 and "Talos API unavailable" in result.stderr
    assert all(record["schematic"] is None for record in records)
    assert all(record["ready"] is None and record["stage"] is None for record in records)


def test_kubectl_failure_keeps_its_exit_status(run_get):
    run_get(["nodes"], expected=7, extra={"MOCK_KUBECTL_FAIL": "true"})


def test_unsupported_flags_are_rejected(run_get):
    run_get(["nodes", "--cluster", "production"], expected=1)
    run_get(["kubeconfig", "development", "--omni"], expected=1)


@pytest.mark.parametrize("kind", ["List", "NodeList"])
def test_node_queries_accept_list_and_nodelist_kinds(run_get, cluster_env, kind):
    (cluster_env.root / "nodes.json").write_text(json.dumps(dict(NODES, kind=kind)))
    assert len(run_get(["nodes"]).stdout.splitlines()) == len(NODES["items"]) + 1
    (cluster_env.root / "nodes.json").write_text(json.dumps(dict(NODES, kind=kind, items=[])))
    before = (cluster_env.root / "topf-calls").read_text()
    assert len(run_get(["nodes"]).stdout.splitlines()) == 1
    assert json.loads(run_get(["nodes", "-o", "json"]).stdout) == []
    assert yaml.safe_load(run_get(["nodes", "-o", "yaml"]).stdout) == []
    assert (cluster_env.root / "topf-calls").read_text() == before
    (cluster_env.root / "nodes.json").write_text(json.dumps(NODES))


def peer(cluster, online=True):
    return {"Online": online, "Tags": ["tag:k8s", "tag:env-" + cluster], "HostName": "ingress-" + cluster + "-0"}


def test_cluster_discovery_selects_online_tailscale_cluster_tags(helper):
    status = {"BackendState": "Running", "Self": peer("self-cluster"), "Peer": {
        "a": peer("development"), "b": peer("development"), "c": peer("production", False),
        "d": {"Online": True, "Tags": ["tag:env-ignore"]}, "e": peer("unknown-to-git"), "f": peer("bad/name")}}
    with patch.object(helper, "command_json", return_value=status), \
         patch.object(helper, "probe_cluster", side_effect=lambda name: {"name": name}) as probe:
        assert helper.discover_clusters() == [{"name": "development"}, {"name": "self-cluster"}, {"name": "unknown-to-git"}]
        assert probe.call_count == 3


def test_api_probes_use_short_dns_names_and_preserve_full_identity(helper):
    with patch.object(helper.subprocess, "run") as curl:
        curl.return_value = subprocess.CompletedProcess([], 0, '{"gitVersion":"v1.37.1"}\n200')
        assert helper.probe_cluster("development")["k8s_version"] == "v1.37.1"
        arguments = curl.call_args.args[0]
        assert arguments[-1] == "https://REDACTED/version"
        assert arguments[arguments.index("--max-time") + 1] == "2"
        assert arguments[arguments.index("--connect-timeout") + 1] == "1"
        assert "--insecure" not in arguments
        for name, short_name in [("production", "prod"), ("development", "dev"), ("unknown-to-git", "unknown-to-git")]:
            cluster = helper.probe_cluster(name)
            assert cluster["name"] == name and cluster["fqdn"] == f"k8s.api.{short_name}REDACTED"
            assert curl.call_args.args[0][-1] == f"https://k8s.api.{short_name}REDACTED/version"


def test_api_probes_treat_401_and_403_as_reachable(helper):
    with patch.object(helper.subprocess, "run") as curl:
        for code, reachable in [(401, True), (403, True), (500, False), (503, False)]:
            curl.return_value = subprocess.CompletedProcess([], 0, "\n" + str(code))
            assert bool(helper.probe_cluster("development")) is reachable


def test_api_probes_exclude_tls_errors_and_timeouts(helper):
    with patch.object(helper.subprocess, "run") as curl:
        curl.return_value = subprocess.CompletedProcess([], 60, "")
        assert helper.probe_cluster("development") is None
        curl.side_effect = subprocess.TimeoutExpired("curl", 3)
        assert helper.probe_cluster("development") is None


def test_stalled_api_probes_finish_within_three_seconds(helper):
    release = threading.Event()

    class StalledAPI(BaseRequestHandler):
        def handle(self):
            release.wait(10)

    real_run = subprocess.run
    status = {"BackendState": "Running", "Peer": {"a": peer("development")}}
    with ThreadingTCPServer(("127.0.0.1", 0), StalledAPI) as stalled:
        stalled.daemon_threads = True
        threading.Thread(target=stalled.serve_forever, daemon=True).start()

        def local_probe(arguments, **kwargs):
            arguments = [*arguments[:-1], f"https://127.0.0.1:{stalled.server_address[1]}/version"]
            return real_run(arguments, **kwargs)

        started = time.monotonic()
        with patch.object(helper, "command_json", return_value=status), \
             patch.object(helper.subprocess, "run", side_effect=local_probe):
            assert helper.discover_clusters() == []
        assert time.monotonic() - started < 3, "offline API probes must run concurrently and fail fast"
        release.set()
        stalled.shutdown()


def test_stalled_tailscale_daemon_fails_within_four_seconds(run_get):
    assert json.loads(run_get(["clusters", "-o", "json"]).stdout) == []
    started = time.monotonic()
    assert "timed out" in run_get(["clusters"], expected=1, extra={"MOCK_TAILSCALE_HANG": "true"}).stderr
    assert time.monotonic() - started < 4


def test_stopped_tailscale_backend_fails(run_get, cluster_env):
    (cluster_env.root / "tailscale.json").write_text(json.dumps({"BackendState": "Stopped"}))
    run_get(["clusters"], expected=1)
    (cluster_env.root / "tailscale.json").write_text(json.dumps({"BackendState": "Running", "Peer": {}}))


def test_kubeconfig_merge_preserves_other_contexts(cluster_env):
    kubeconfig = cluster_env.root / "kubeconfig"
    original = {"apiVersion": "v1", "kind": "Config", "current-context": "unrelated",
                "contexts": [{"name": "unrelated", "context": {"cluster": "unrelated", "user": "unrelated"}}]}
    kubeconfig.write_text(yaml.safe_dump(original))
    env = dict(cluster_env.env, KUBECONFIG=str(kubeconfig))

    result = subprocess.run([str(HSCTL), "get", "kubeconfig", "development"], env=env,
                            text=True, capture_output=True, timeout=30)
    assert result.returncode == 1
    assert yaml.safe_load(kubeconfig.read_text()) == original, "unreachable clusters must leave kubeconfig unchanged"

    script = '''source "$HSCTL_ROOT/hsctl.d/_lib.sh"
source "$HSCTL_ROOT/hsctl.d/get.sh"
get_clusters() { echo '[{"name":"development"}]'; }
get_kubeconfig development
'''
    failed = subprocess.run(["bash", "-euo", "pipefail", "-c", script],
                            env=dict(env, MOCK_YQ_FAIL="true"), text=True, capture_output=True, timeout=30)
    assert failed.returncode != 0
    assert yaml.safe_load(kubeconfig.read_text()) == original, "a failed merge must preserve the previous file"

    ok = subprocess.run(["bash", "-euo", "pipefail", "-c", script], env=env,
                        text=True, capture_output=True, timeout=30)
    assert ok.returncode == 0
    merged = yaml.safe_load(kubeconfig.read_text())
    assert merged["current-context"] == "development" and len(merged["contexts"]) == 2
    assert merged["clusters"][0]["cluster"] == {"server": "https://REDACTED"}
    assert merged["users"][0]["user"]["exec"]["command"] == "kubectl"
    assert kubeconfig.stat().st_mode & 0o077 == 0 and not list(cluster_env.root.glob(".hsctl-kubeconfig.*"))


@pytest.mark.parametrize("cluster,short_name", [
    ("production", "prod"), ("development", "dev"), ("prod", "prod"),
    ("dev", "dev"), ("other-cluster", "other-cluster"),
])
def test_argocd_and_kubeconfig_agree_on_short_dns_names(cluster_env, cluster, short_name):
    for action in ["login", "open"]:
        result = subprocess.run([str(HSCTL), "argocd", action, cluster], env=cluster_env.env,
                                text=True, capture_output=True, check=True, timeout=5)
        expected = (["login", f"argocd.{short_name}REDACTED", "--sso"] if action == "login"
                    else [f"https://argocd.{short_name}REDACTED"])
        assert json.loads(result.stdout) == expected

    kubeconfig = cluster_env.root / "kubeconfig"
    config_script = '''source "$HSCTL_ROOT/hsctl.d/_lib.sh"
source "$HSCTL_ROOT/hsctl.d/get.sh"
_hsctl_write_kubeconfig_direct "$1" "$2"
'''
    subprocess.run(["bash", "-euo", "pipefail", "-c", config_script, "hsctl-test", cluster, str(kubeconfig)],
                   env=cluster_env.env, text=True, capture_output=True, check=True, timeout=5)
    merged = yaml.safe_load(kubeconfig.read_text())
    assert merged["current-context"] == cluster
    entry = next(entry for entry in merged["clusters"] if entry["name"] == cluster)
    assert entry["cluster"]["server"] == f"https://k8s.api.{short_name}REDACTED"


def test_ansible_inventory_lists_clusters_from_the_checkout(cluster_env):
    for cluster in ["production", "development"]:
        project = cluster_env.root / "clusters" / cluster
        project.mkdir(parents=True, exist_ok=True)
        (project / "topf.yaml").write_text("clusterName: " + cluster)
    inventory = REPO / "infra/ansible/inventory/clusters"

    result = subprocess.run([str(inventory), "--list"], env=cluster_env.env, text=True, capture_output=True, check=True)
    assert json.loads(result.stdout)["clusters"]["hosts"] == ["development", "production"]

    result = subprocess.run([str(inventory), "--host", "development"], env=cluster_env.env,
                            text=True, capture_output=True, check=True)
    assert json.loads(result.stdout) == {}

    result = subprocess.run(["ansible-inventory", "-i", str(inventory.parent), "--list"],
                            env=dict(cluster_env.env, ANSIBLE_LOCAL_TEMP=str(cluster_env.root / "ansible-temp")),
                            text=True, capture_output=True, check=True)
    assert json.loads(result.stdout)["clusters"]["hosts"] == ["development", "production"]
    assert not (REPO / "infra/ansible/inventory/machines").exists()
