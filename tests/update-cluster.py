#!/usr/bin/env python3
"""Exercise update-cluster with fake cluster APIs and native upgrade commands."""
import atexit
import copy
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

import yaml


REPO = Path(__file__).resolve().parents[1]


def executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix="cluster-update-test-") as temporary:
    root = Path(temporary)
    shutil.copytree(REPO / "infra/ansible/playbooks", root / "infra/ansible/playbooks")
    shutil.copytree(REPO / "infra/ansible/tasks", root / "infra/ansible/tasks")
    shutil.copytree(REPO / "infra/ansible/roles", root / "infra/ansible/roles")
    tools = root / "bin"
    tools.mkdir()
    inventory = root / "inventory.yaml"
    inventory.write_text(yaml.safe_dump({"clusters": {"hosts": {
        cluster: {"ansible_connection": "local", "talos_cluster_name": cluster,
                  "talos_shortname": shortname}
        for cluster, shortname in [("production", "prod"), ("development", "dev")]
    }}}))
    configs = {}
    for cluster in ["development", "production"]:
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
cluster = next(name for name in ["development", "production"] if json.loads((root / (name + "-desired.json")).read_text())["nodes"][0]["ip"] == node_ip)
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
''')
    # Mock only the API boundary: use the production Ansible task files unchanged.
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
    # Select the mock API cluster from each TOPF nodes query, also covering serial hosts.
    script = (root / "hsctl").read_text().replace('elif "nodes" in args:', 'elif "nodes" in args:\n    (root / "active-cluster").write_text(cluster)')
    executable(root / "hsctl", script)
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
    (root / "ansible.cfg").write_text(f"[defaults]\ninterpreter_python={sys.executable}\npipelining=true\nroles_path={root / 'infra/ansible/roles'}\n")
    environment = dict(os.environ, MOCK_ROOT=str(root), HSCTL_REPO_ROOT=str(root),
                       PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       ANSIBLE_COLLECTIONS_PATH=str(root / "collections"),
                       ANSIBLE_LOCAL_TEMP=str(root / "ansible-tmp"),
                       ACTIONS_ID_TOKEN_REQUEST_URL="http://127.0.0.1:" + str(oidc.server_port) + "/oidc",
                       ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-request-token",  # pragma: allowlist secret
                       ANSIBLE_NOCOLOR="1", ANSIBLE_CONFIG=str(root / "ansible.cfg"))

    @contextmanager
    def scenario(name, **options):
        with tempfile.TemporaryDirectory(prefix="case-", dir=root) as directory:
            case = Path(directory)
            (case / "hsctl").symlink_to(root / "hsctl")
            tokens_path = "/" + case.name
            case_environment = dict(environment, MOCK_ROOT=str(case), HSCTL_REPO_ROOT=str(case),
                                    ANSIBLE_LOCAL_TEMP=str(case / "ansible-tmp"),
                                    ACTIONS_ID_TOKEN_REQUEST_URL=f"http://127.0.0.1:{oidc.server_port}{tokens_path}")
            yield run_scenario(name, case, case_environment, tokens_path, **options)
        print(f"PASS: {name}", flush=True)

    def run_scenario(name, case, case_environment, tokens_path, preview=False,
                     cluster="development", expected=0, enabled=True, credentials_current=False, **overrides):
        credentials = {"/k8s/argocd/deploy-key": {"sshPrivateKey": "private-test-rotated-deploy-key"},  # pragma: allowlist secret
                       "/k8s/infisical": {"INFISICAL_OPERATOR_CLIENT_ID": "test-client",
                                          "INFISICAL_OPERATOR_CLIENT_SECRET": "private-test-rotated-operator"}}  # pragma: allowlist secret
        (case / "service-credentials.json").write_text(json.dumps(credentials))
        service_objects = {
            "/" + ns: dict(apiVersion="v1", kind="Namespace", metadata=dict(name=ns)) for ns in ["argocd", "infisical"]
        }
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
        for current, config in configs.items():
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
        command = ["ansible-playbook", "-i", str(inventory), str(root / "infra/ansible/playbooks/update-cluster.yml"),
                   "-e", "dry_run=" + str(preview).lower()]
        if cluster:
            command += ["--limit", cluster]
        result = subprocess.run(command, env=case_environment, text=True, capture_output=True, timeout=180)
        assert result.returncode == expected, f"{name}: {result.stdout}\n{result.stderr}"
        assert "private-test-" not in result.stdout and "private-test-" not in result.stderr
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        assert all(not Path(call["workspace"]).exists() for call in calls), name + ": leaked credentials"
        for current in configs:
            objects = json.loads((case / (current + "-service-objects.json")).read_text())
            reconciled = any(call["tool"] == "k8s" and call["cluster"] == current for call in calls)
            assert objects == (service_objects if reconciled and not preview and not overrides.get('fail_credentials') else initial_objects)
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
        assert authenticated == issued_tokens.get(tokens_path, [])
        assert len(authenticated) == len(set(authenticated))
        return calls, mutations

    def successful_upgrades():
        with scenario("Preview makes no cluster changes", preview=True) as (calls, mutations):
            assert not mutations and any("upgrade-k8s" in call["args"] for call in calls)
            assert sum("nodes" in call["args"] for call in calls) == 1
        with scenario("Talos upgrades before Kubernetes and config apply") as (calls, mutations):
            assert [next(action for action in ["upgrade", "upgrade-k8s", "apply"] if action in call["args"]) for call in mutations] == ["upgrade", "upgrade-k8s", "apply"]
            assert sum("nodes" in call["args"] for call in calls) == 2
        with scenario(
            "Unchanged versions still reconcile config and rotated service credentials",
            talos=["1.14.5"], kubelets=["1.37.1"], components=["1.37.1"] * 3, server="1.37.1",
        ) as (calls, mutations):
            assert len(mutations) == 1 and "apply" in mutations[0]["args"]
            assert sum("nodes" in call["args"] for call in calls) == 1
        with scenario("Already-current service credentials remain unchanged", credentials_current=True):
            pass
        with scenario(
            "Only Talos upgrades when Kubernetes is current",
            kubelets=["1.37.1"], components=["1.37.1"] * 3, server="1.37.1",
        ) as (_, mutations):
            assert len(mutations) == 2 and not any("upgrade-k8s" in call["args"] for call in mutations)
        with scenario("Only Kubernetes upgrades when Talos is current", talos=["1.14.5"]) as (_, mutations):
            assert len(mutations) == 2 and not any("upgrade" in call["args"] for call in mutations)
        with scenario(
            "An unfinished control-plane upgrade is resumed",
            talos=["1.14.5"], kubelets=["1.37.1"], components=["1.37.1", "1.37.0", "1.37.1"], server="1.37.1",
        ) as (_, mutations):
            assert "upgrade-k8s" in mutations[0]["args"]
        with scenario("One Kubernetes upgrade covers all three control planes", cluster="production") as (_, mutations):
            assert sum("upgrade-k8s" in call["args"] for call in mutations) == 1

    def rejected_upgrades():
        for name, options in [
            ("Talos downgrades are rejected", dict(talos=["1.14.6"])),
            ("Talos minor versions cannot be skipped", dict(talos=["1.12.9"])),
            ("Kubernetes downgrades are rejected", dict(server="1.37.2")),
            ("Kubernetes minor versions cannot be skipped", dict(kubelets=["1.35.9"])),
            ("Unreachable nodes stop the upgrade", dict(unreachable=True)),
            ("An empty node response stops the upgrade", dict(empty=True)),
            ("Unknown node IPs stop the upgrade", dict(wrong_ip=True)),
            ("Failed Kubernetes preflight stops all upgrades", dict(fail_preflight=True)),
        ]:
            with scenario(name, expected=2, **options) as (_, mutations):
                assert not mutations

    def failed_upgrades():
        with scenario("Failed credential reconciliation stops upgrades and removes credentials", expected=2, fail_credentials=True) as (_, mutations):
            assert not mutations
        with scenario("A failed Talos upgrade stops Kubernetes and config apply", expected=2, fail_os=True) as (_, mutations):
            assert len(mutations) == 1 and "upgrade" in mutations[0]["args"]
        with scenario("A failed Kubernetes upgrade stops config apply", expected=2, fail_k8s=True) as (_, mutations):
            assert not any("apply" in call["args"] for call in mutations)
        with scenario("Config apply waits for every component to finish upgrading", expected=2, partial_k8s=True) as (_, mutations):
            assert not any("apply" in call["args"] for call in mutations)
        with scenario("A failed config apply removes temporary credentials", expected=2, fail_apply=True) as (_, mutations):
            assert "apply" in mutations[-1]["args"]

    def serial_rollouts():
        with scenario("New clusters are skipped before fetching credentials", enabled=False) as (calls, _):
            assert not calls
        with scenario("A development failure stops production", cluster=None, expected=2, fail_os=True) as (calls, _):
            assert {call["cluster"] for call in calls} == {"development"}
        with scenario("Development updates before production", cluster=None) as (calls, _):
            sequence = [call["cluster"] for call in calls]
            assert set(sequence) == {"development", "production"}
            assert sequence == sorted(sequence)

    with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as executor:
        checks = [successful_upgrades, rejected_upgrades, failed_upgrades, serial_rollouts]
        futures = [executor.submit(check) for check in checks]
        for future in futures:
            future.result()

    executable(tools / "ansible-galaxy", "#!/bin/sh\nexit 0\n")
    executable(tools / "infisical", '''#!/usr/bin/env python3
import json, sys
assert sys.argv[1] == "export"
print(json.dumps([dict(key="test", value="private-test-cli-credential")]))
''')
    executable(tools / "ansible-playbook", '''#!/usr/bin/env python3
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
                            env=environment, text=True, capture_output=True, check=True)
    arguments = json.loads(result.stdout)
    assert "dry_run=true" in arguments and "target=development" in arguments
    extra_vars = Path(arguments[arguments.index("--extra-vars") + 1][1:])
    assert not extra_vars.exists(), "local updates must clean their private credential file"
    print("PASS: hsctl forwards cluster, preview and private service credentials, then removes the file", flush=True)
