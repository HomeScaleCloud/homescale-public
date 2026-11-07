"""Exercise update-cluster with fake cluster APIs and native upgrade commands."""
import atexit
import copy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import types

import pytest
import yaml

from conftest import REPO

CLUSTERS = [("production", "prod"), ("development", "dev")]


def bump_patch(version):
    """A version strictly newer than `version`, same major.minor — simulates a cluster
    that's ahead of its pin, without hardcoding a patch number that drifts out of date
    every time the real pin is bumped (see the kubernetesVersion 1.37.1 -> 1.37.2 bump
    that broke these scenarios' hardcoded '1.37.1' baseline)."""
    major, minor, patch = version.split(".")
    return f"{major}.{minor}.{int(patch) + 1}"


@pytest.fixture(scope="module")
def env(tmp_path_factory, executable):
    root = tmp_path_factory.mktemp("cluster-update")
    shutil.copytree(REPO / "infra/ansible/playbooks", root / "infra/ansible/playbooks")
    shutil.copytree(REPO / "infra/ansible/tasks", root / "infra/ansible/tasks")
    shutil.copytree(REPO / "infra/ansible/roles", root / "infra/ansible/roles")
    tools = root / "bin"
    tools.mkdir()
    inventory = root / "inventory.yaml"
    inventory.write_text(yaml.safe_dump({"clusters": {"hosts": {
        cluster: {"ansible_connection": "local", "talos_cluster_name": cluster, "talos_shortname": shortname}
        for cluster, shortname in CLUSTERS
    }}}))

    configs = {}
    for cluster, _ in CLUSTERS:
        config = yaml.safe_load((REPO / "clusters" / cluster / "topf.yaml").read_text())
        config["data"]["bootstrapComplete"] = True
        configs[cluster] = config
        (root / "clusters" / cluster).mkdir(parents=True)
        (root / "clusters" / cluster / "topf.yaml").write_text(yaml.safe_dump(config))

    executable(root / "hsctl", '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
args = sys.argv[1:]
cluster = args[args.index("--cluster") + 1]
state_file = root / (cluster + "-state.json")
state = json.loads(state_file.read_text())
config = json.loads((root / (cluster + "-desired.json")).read_text())
workspace = pathlib.Path(os.environ["KUBECONFIG"]).parent
assert workspace.stat().st_mode & 0o077 == 0
bundle = pathlib.Path(os.environ["HSCTL_TOPF_SECRETS_FILE"])
assert bundle.read_text() == "private-test-CA" and bundle.stat().st_mode & 0o077 == 0
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps(dict(tool="topf", cluster=cluster, args=args, workspace=str(workspace))) + "\\n")
if "kubeconfig" in args or "talosconfig" in args:
    print("private-test-client-config")
elif "nodes" in args:
    (root / "active-cluster").write_text(cluster)
    print(json.dumps([dict(node=node, talosversion=state["talos"][i],
                          machinestatus=dict(status=dict(ready=True)),
                          error="unreachable" if state.get("unreachable") else "")
                      for i, node in enumerate(config["nodes"])] if not state.get("empty") else []))
elif "upgrade" in args:
    needed = set(state["talos"]) != {config["talosVersion"]} or state.get("schematic_drift", False)
    if "--dry-run" in args:
        print("Talos upgrade needed:", needed)
        sys.exit(2 if needed else 0)
    if state.get("fail_os"):
        sys.exit(7)
    state["talos"] = [config["talosVersion"]] * len(config["nodes"])
    state["schematic_drift"] = False
    state_file.write_text(json.dumps(state))
elif "apply" in args:
    if "--dry-run" in args:
        print("redacted config diff")
        sys.exit(2)
    assert set(state["talos"]) == {config["talosVersion"]}
    assert set(state["kubelets"] + state["components"] + [state["server"]]) == {config["kubernetesVersion"]}
    if state.get("fail_apply"):
        sys.exit(7)
else:
    raise AssertionError(args)
''')
    executable(tools / "talosctl", '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
args = sys.argv[1:]
assert "upgrade-k8s" in args
credential = pathlib.Path(args[args.index("--talosconfig") + 1])
assert credential.stat().st_mode & 0o077 == 0
node_ip = args[args.index("--nodes") + 1]
cluster = next(name for name, _ in %r if json.loads((root / (name + "-desired.json")).read_text())["nodes"][0]["ip"] == node_ip)
state_file = root / (cluster + "-state.json")
state = json.loads(state_file.read_text())
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps(dict(tool="talosctl", cluster=cluster, args=args, workspace=str(credential.parent))) + "\\n")
if "--dry-run" in args:
    if state.get("fail_preflight"):
        sys.exit(7)
    print("Kubernetes upgrade preview")
else:
    if state.get("fail_k8s"):
        sys.exit(7)
    target = args[args.index("--to") + 1]
    state["kubelets"] = [target] * len(state["kubelets"])
    state["components"] = [target] * len(state["components"])
    state["server"] = target
    if state.get("partial_k8s"):
        state["components"][-1] = "1.37.0"
    state_file.write_text(json.dumps(state))
''' % (CLUSTERS,))

    collection_root = root / "collections/ansible_collections"
    module_header = '''from ansible.module_utils.basic import AnsibleModule
import json, os, pathlib
root = pathlib.Path(os.environ["MOCK_ROOT"])
'''
    modules = {
        ("infisical/vault", "login"): '''module = AnsibleModule(argument_spec={key: dict(type="str", no_log=True) for key in ["url", "auth_method", "identity_id", "jwt"]})
assert module.params["jwt"].startswith("fresh-test-jwt-")
with (root / "auth.jsonl").open("a") as stream:
    stream.write(json.dumps(module.params["jwt"]) + "\\n")
module.exit_json(changed=False, login_data={"test": "auth"})
''',
        ("infisical/vault", "read_secrets"): '''module = AnsibleModule(argument_spec={"login_data": dict(type="dict", no_log=True), "project_id": {}, "env_slug": {}, "path": {}, "as_dict": dict(type="bool")})
assert module.params["env_slug"] == "prod"
assert module.params["login_data"] == {"test": "auth"}
path = module.params["path"]
if path in ["/k8s/talos/dev", "/k8s/talos/prod"]:
    secrets = {"SECRETS_YAML": "private-test-CA"}  # pragma: allowlist secret
else:
    secrets = json.loads((root / "service-credentials.json").read_text())[path]
module.exit_json(changed=False, secrets=secrets)
''',
        ("kubernetes/core", "k8s"): '''module = AnsibleModule(argument_spec={"kubeconfig": {}, "state": {}, "api_version": {}, "kind": {}, "name": {}, "definition": dict(type="dict")}, supports_check_mode=True)
assert module.params["state"] == "present"
workspace = pathlib.Path(module.params["kubeconfig"]).parent
cluster = (root / "active-cluster").read_text()
state = json.loads((root / (cluster + "-state.json")).read_text())
definition = module.params["definition"] or dict(apiVersion="v1", kind="Namespace", metadata=dict(name=module.params["name"]))
key = definition["metadata"].get("namespace", "") + "/" + definition["metadata"]["name"]
objects_file = root / (cluster + "-service-objects.json")
objects = json.loads(objects_file.read_text())
changed = objects.get(key) != definition
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps(dict(tool="k8s", cluster=cluster, args=["--dry-run"] if module.check_mode else [],
                                workspace=str(workspace), changed=changed, key=key)) + "\\n")
if state.get("fail_credentials") and definition["kind"] == "Secret":
    module.fail_json(msg="credential update failed")
if not module.check_mode:
    objects[key] = definition
    objects_file.write_text(json.dumps(objects))
module.exit_json(changed=changed)
''',
        ("kubernetes/core", "k8s_cluster_info"): '''module = AnsibleModule(argument_spec={"kubeconfig": {}})
cluster = (root / "active-cluster").read_text()
state = json.loads((root / (cluster + "-state.json")).read_text())
module.exit_json(changed=False, version={"server": {"kubernetes": {"gitVersion": "v" + state["server"]}}})
''',
        ("kubernetes/core", "k8s_info"): '''module = AnsibleModule(argument_spec={key: {} for key in ["kubeconfig", "api_version", "kind", "namespace"]})
cluster = (root / "active-cluster").read_text()
state = json.loads((root / (cluster + "-state.json")).read_text())
config = json.loads((root / (cluster + "-desired.json")).read_text())
if module.params["kind"] == "Node":
    resources = [dict(metadata=dict(name="talos-test-" + str(i)), status=dict(addresses=[dict(type="InternalIP", address="192.0.2.99" if state.get("wrong_ip") else node["ip"])], nodeInfo=dict(kubeletVersion="v" + state["kubelets"][i]), conditions=[dict(type="Ready", status="True")])) for i, node in enumerate(config["nodes"])]
else:
    resources = []
    index = 0
    for node in config["nodes"]:
        if node["role"] != "control-plane":
            continue
        for component in ["kube-apiserver", "kube-controller-manager", "kube-scheduler"]:
            resources.append(dict(metadata=dict(name=component + "-talos-test-" + str(config["nodes"].index(node))), spec=dict(containers=[dict(image="registry.k8s.io/" + component + ":v" + state["components"][index])])))
            index += 1
module.exit_json(changed=False, resources=resources)
''',
    }
    for (collection, name), code in modules.items():
        directory = collection_root / collection / "plugins/modules"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / (name + ".py")).write_text(module_header + code)

    issued_tokens = {}

    class OIDCHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            assert self.headers["Authorization"] == "Bearer fake-request-token"
            tokens = issued_tokens.setdefault(self.path, [])
            token = "fresh-test-jwt-" + self.path[1:] + "-" + str(len(tokens))
            tokens.append(token)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"value": token}).encode())

        def log_message(self, *_args):
            pass

    oidc = ThreadingHTTPServer(("127.0.0.1", 0), OIDCHandler)
    threading.Thread(target=oidc.serve_forever, daemon=True).start()
    atexit.register(oidc.shutdown)
    (root / "ansible.cfg").write_text(
        f"[defaults]\ninterpreter_python={sys.executable}\npipelining=true\nroles_path={root / 'infra/ansible/roles'}\n")
    environment = dict(os.environ, MOCK_ROOT=str(root), HSCTL_REPO_ROOT=str(root),
                       PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       ANSIBLE_COLLECTIONS_PATH=str(root / "collections"),
                       ANSIBLE_LOCAL_TEMP=str(root / "ansible-tmp"),
                       ACTIONS_ID_TOKEN_REQUEST_URL="http://127.0.0.1:" + str(oidc.server_port) + "/oidc",
                       ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-request-token",  # pragma: allowlist secret
                       ANSIBLE_NOCOLOR="1", ANSIBLE_CONFIG=str(root / "ansible.cfg"))
    return types.SimpleNamespace(root=root, tools=tools, inventory=inventory, configs=configs,
                                 environment=environment, oidc=oidc, issued_tokens=issued_tokens)


@pytest.fixture
def run_scenario(env):
    """Run update-cluster.yml in an isolated case directory and return (calls, mutations).

    Each call gets its own scratch directory and mock cluster state, so scenarios
    are independent even though they share the module-scoped `env` setup above.
    """
    def invoke(name, preview=False, cluster="development", expected=0, enabled=True,
               credentials_current=False, **overrides):
        with tempfile.TemporaryDirectory(prefix="case-", dir=env.root) as directory:
            case = Path(directory)
            (case / "hsctl").symlink_to(env.root / "hsctl")
            tokens_path = "/" + case.name
            case_environment = dict(env.environment, MOCK_ROOT=str(case), HSCTL_REPO_ROOT=str(case),
                                    ANSIBLE_LOCAL_TEMP=str(case / "ansible-tmp"),
                                    ACTIONS_ID_TOKEN_REQUEST_URL=f"http://127.0.0.1:{env.oidc.server_port}{tokens_path}")

            credentials = {"/k8s/argocd/deploy-key": {"sshPrivateKey": "private-test-rotated-deploy-key"},  # pragma: allowlist secret
                           "/k8s/infisical": {"INFISICAL_OPERATOR_CLIENT_ID": "test-client",
                                              "INFISICAL_OPERATOR_CLIENT_SECRET": "private-test-rotated-operator"}}  # pragma: allowlist secret
            (case / "service-credentials.json").write_text(json.dumps(credentials))
            service_objects = {"/" + ns: dict(apiVersion="v1", kind="Namespace", metadata=dict(name=ns))
                               for ns in ["argocd", "infisical"]}
            service_objects.update({
                "argocd/homescale-k8s-deploy-key": dict(apiVersion="v1", kind="Secret", metadata=dict(
                    name="homescale-k8s-deploy-key", namespace="argocd", labels={"argocd.argoproj.io/secret-type": "repository"}),
                    stringData=dict(url="git@github.com:HomeScaleCloud/homescale.git",
                                    sshPrivateKey=credentials["/k8s/argocd/deploy-key"]["sshPrivateKey"])),
                "infisical/infisical-operator-auth": dict(apiVersion="v1", kind="Secret", metadata=dict(
                    name="infisical-operator-auth", namespace="infisical"), stringData=dict(
                    clientId="test-client", clientSecret=credentials["/k8s/infisical"]["INFISICAL_OPERATOR_CLIENT_SECRET"])),
            })
            initial_objects = copy.deepcopy(service_objects)
            if not credentials_current:
                initial_objects["argocd/homescale-k8s-deploy-key"]["stringData"]["sshPrivateKey"] = "private-test-old-key"  # pragma: allowlist secret
                initial_objects["infisical/infisical-operator-auth"]["stringData"]["clientSecret"] = "private-test-old-operator"  # pragma: allowlist secret
            for current, config in env.configs.items():
                desired = copy.deepcopy(config)
                desired["data"]["bootstrapComplete"] = enabled
                (case / "clusters" / current).mkdir(parents=True)
                (case / "clusters" / current / "topf.yaml").write_text(yaml.safe_dump(desired))
                (case / (current + "-desired.json")).write_text(json.dumps(desired))
                count = len(config["nodes"])
                state = dict(talos=["1.14.4"] * count, kubelets=["1.37.0"] * count,
                             components=["1.37.0"] * count * 3, server="1.37.0")
                state.update(overrides)
                (case / (current + "-state.json")).write_text(json.dumps(state))
                (case / (current + "-service-objects.json")).write_text(json.dumps(initial_objects))

            log = case / "calls.jsonl"
            command = ["ansible-playbook", "-i", str(env.inventory),
                       str(env.root / "infra/ansible/playbooks/update-cluster.yml"), "-e", "dry_run=" + str(preview).lower()]
            if cluster:
                command += ["--limit", cluster]
            result = subprocess.run(command, env=case_environment, text=True, capture_output=True, timeout=180)
            assert result.returncode == expected, f"{name}: {result.stdout}\n{result.stderr}"
            assert "private-test-" not in result.stdout and "private-test-" not in result.stderr

            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            assert all(not Path(call["workspace"]).exists() for call in calls), name + ": leaked credentials"
            for current in env.configs:
                objects = json.loads((case / (current + "-service-objects.json")).read_text())
                reconciled = any(call["tool"] == "k8s" and call["cluster"] == current for call in calls)
                assert objects == (service_objects if reconciled and not preview and not overrides.get("fail_credentials") else initial_objects)
            service_calls = [call for call in calls if call["tool"] == "k8s"]
            if preview:
                assert all("--dry-run" in call["args"] for call in service_calls)
            if expected == 0 and enabled:
                assert service_calls, "Every update must reconcile service credentials, even when versions match"
                assert any(call["changed"] for call in service_calls) != credentials_current
            mutations = [call for call in calls if "--dry-run" not in call["args"] and
                         any(action in call["args"] for action in ["upgrade", "upgrade-k8s", "apply"])]
            auth_log = case / "auth.jsonl"
            authenticated = [json.loads(line) for line in auth_log.read_text().splitlines()] if auth_log.exists() else []
            assert authenticated == env.issued_tokens.get(tokens_path, [])
            assert len(authenticated) == len(set(authenticated))
            return calls, mutations
    return invoke


# --- Successful upgrades ---

def test_preview_makes_no_cluster_changes(run_scenario):
    calls, mutations = run_scenario("preview", preview=True)
    assert not mutations and any("upgrade-k8s" in call["args"] for call in calls)
    assert sum("nodes" in call["args"] for call in calls) == 1


def test_talos_upgrades_before_kubernetes_and_config_apply(run_scenario):
    calls, mutations = run_scenario("ordering")
    assert [next(action for action in ["upgrade", "upgrade-k8s", "apply"] if action in call["args"])
            for call in mutations] == ["upgrade", "upgrade-k8s", "apply"]
    assert sum("nodes" in call["args"] for call in calls) == 2


def test_unchanged_versions_still_reconcile_config_and_rotated_credentials(run_scenario, env):
    current_k8s = env.configs["development"]["kubernetesVersion"]
    calls, mutations = run_scenario("unchanged", talos=[env.configs["development"]["talosVersion"]],
                                    kubelets=[current_k8s], components=[current_k8s] * 3, server=current_k8s)
    assert len(mutations) == 1 and "apply" in mutations[0]["args"]
    assert sum("nodes" in call["args"] for call in calls) == 1


def test_already_current_service_credentials_remain_unchanged(run_scenario):
    run_scenario("current-credentials", credentials_current=True)


def test_only_talos_upgrades_when_kubernetes_is_current(run_scenario, env):
    current_k8s = env.configs["development"]["kubernetesVersion"]
    _, mutations = run_scenario("talos-only", kubelets=[current_k8s], components=[current_k8s] * 3, server=current_k8s)
    assert len(mutations) == 2 and not any("upgrade-k8s" in call["args"] for call in mutations)


def test_only_kubernetes_upgrades_when_talos_is_current(run_scenario):
    _, mutations = run_scenario("k8s-only", talos=["1.14.5"])
    assert len(mutations) == 2 and not any("upgrade" in call["args"] for call in mutations)


def test_an_unfinished_control_plane_upgrade_is_resumed(run_scenario):
    _, mutations = run_scenario("resume", talos=["1.14.5"], kubelets=["1.37.1"],
                                components=["1.37.1", "1.37.0", "1.37.1"], server="1.37.1")
    assert "upgrade-k8s" in mutations[0]["args"]


def test_one_kubernetes_upgrade_covers_all_control_planes(run_scenario):
    _, mutations = run_scenario("fan-out", cluster="production")
    assert sum("upgrade-k8s" in call["args"] for call in mutations) == 1


# --- Rejected upgrades ---

@pytest.mark.parametrize("name,options", [
    ("Talos downgrades are rejected", dict(talos=["1.14.6"])),
    ("Talos minor versions cannot be skipped", dict(talos=["1.12.9"])),
    ("Kubernetes downgrades are rejected", dict(server="CURRENT_K8S_PLUS_ONE")),
    ("Kubernetes minor versions cannot be skipped", dict(kubelets=["1.35.9"])),
    ("Unreachable nodes stop the upgrade", dict(unreachable=True)),
    ("An empty node response stops the upgrade", dict(empty=True)),
    ("Unknown node IPs stop the upgrade", dict(wrong_ip=True)),
    ("Failed Kubernetes preflight stops all upgrades", dict(fail_preflight=True)),
])
def test_rejected_upgrades_make_no_mutations(run_scenario, env, name, options):
    # A live server version newer than the real pin simulates a downgrade attempt,
    # without hardcoding a number that goes stale every time the pin is bumped.
    if options.get("server") == "CURRENT_K8S_PLUS_ONE":
        options = dict(options, server=bump_patch(env.configs["development"]["kubernetesVersion"]))
    _, mutations = run_scenario(name, expected=2, **options)
    assert not mutations


# --- Failed upgrades ---

def test_failed_credential_reconciliation_stops_upgrades(run_scenario):
    _, mutations = run_scenario("fail-credentials", expected=2, fail_credentials=True)
    assert not mutations


def test_failed_talos_upgrade_stops_kubernetes_and_apply(run_scenario):
    _, mutations = run_scenario("fail-os", expected=2, fail_os=True)
    assert len(mutations) == 1 and "upgrade" in mutations[0]["args"]


def test_failed_kubernetes_upgrade_stops_config_apply(run_scenario):
    _, mutations = run_scenario("fail-k8s", expected=2, fail_k8s=True)
    assert not any("apply" in call["args"] for call in mutations)


def test_config_apply_waits_for_every_component(run_scenario):
    _, mutations = run_scenario("partial-k8s", expected=2, partial_k8s=True)
    assert not any("apply" in call["args"] for call in mutations)


def test_failed_config_apply_removes_temporary_credentials(run_scenario):
    _, mutations = run_scenario("fail-apply", expected=2, fail_apply=True)
    assert "apply" in mutations[-1]["args"]


# --- Serial rollouts ---

def test_new_clusters_are_skipped_before_fetching_credentials(run_scenario):
    calls, _ = run_scenario("skip-new", enabled=False)
    assert not calls


def test_a_development_failure_stops_production(run_scenario):
    calls, _ = run_scenario("dev-fails", cluster=None, expected=2, fail_os=True)
    assert {call["cluster"] for call in calls} == {"development"}


def test_development_updates_before_production(run_scenario):
    calls, _ = run_scenario("serial-order", cluster=None)
    sequence = [call["cluster"] for call in calls]
    assert set(sequence) == {"development", "production"}
    assert sequence == sorted(sequence)


def test_hsctl_forwards_cluster_preview_and_service_credentials(env, executable):
    executable(env.tools / "ansible-galaxy", "#!/bin/sh\nexit 0\n")
    executable(env.tools / "infisical", '''#!/usr/bin/env python3
import json, sys
assert sys.argv[1] == "export"
print(json.dumps([dict(key="test", value="private-test-cli-credential")]))
''')
    executable(env.tools / "ansible-playbook", '''#!/usr/bin/env python3
import json, pathlib, sys
args = sys.argv[1:]
extra = pathlib.Path(args[args.index("--extra-vars") + 1][1:])
assert extra.stat().st_mode & 0o077 == 0
values = json.loads(extra.read_text())
assert values["hsctl_local"] is True
assert set(values["hsctl_local_secrets"]) == {"argocd_deploy_key", "infisical_operator"}
assert all(item["test"] == "private-test-cli-credential" for item in values["hsctl_local_secrets"].values())
print(json.dumps(args))
''')
    result = subprocess.run([str(REPO / "hsctl"), "run", "update-cluster", "--cluster", "development", "-e", "local", "--dry-run"],
                            env=env.environment, text=True, capture_output=True, check=True)
    arguments = json.loads(result.stdout)
    assert "dry_run=true" in arguments and "target=development" in arguments
    extra_vars = Path(arguments[arguments.index("--extra-vars") + 1][1:])
    assert not extra_vars.exists(), "local updates must clean their private credential file"
