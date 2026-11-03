#!/usr/bin/env python3
"""Exercise secret recovery and bootstrap-cluster sequencing with mocked services."""
import base64
import copy
from concurrent.futures import ThreadPoolExecutor
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import yaml


REPO = Path(__file__).resolve().parents[1]


def run(command, environment, expected=0, stdin=None):
    result = subprocess.run(command, env=environment, text=True, input=stdin,
                            capture_output=True, timeout=120)
    assert result.returncode == expected, f"{command[0]} exited {result.returncode}: {result.stderr}"
    return result


def executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix="topf-regression-") as temporary:
    scratch = Path(temporary)
    shutil.copytree(REPO / "hsctl.d", scratch / "hsctl.d")
    shutil.copytree(REPO / "infra/topf", scratch / "infra/topf")
    shutil.copyfile(REPO / "hsctl", scratch / "hsctl")
    (scratch / "hsctl").chmod(0o755)
    for cluster in ["development", "production"]:
        project = scratch / "clusters" / cluster
        project.mkdir(parents=True)
        shutil.copyfile(REPO / "clusters" / cluster / "topf.yaml", project / "topf.yaml")
    project = scratch / "clusters/development"
    mock_bin = scratch / "bin"
    mock_bin.mkdir()
    environment = dict(os.environ, HSCTL_REPO_ROOT=str(scratch), MOCK_ROOT=str(scratch),
                       PATH=str(mock_bin) + os.pathsep + os.environ["PATH"],
                       ANSIBLE_LOCAL_TEMP=str(scratch / "ansible"))
    initialization = dict(environment, HSCTL_TOPF_INIT_SECRETS="true")  # pragma: allowlist secret
    executable(mock_bin / "infisical", """#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
with (root / "calls").open("a") as logfile:
    logfile.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1] == "export":
    if os.environ.get("MOCK_EXPORT_FAIL") == "true":
        print("permission denied", file=sys.stderr)
        sys.exit(9)
    print((root / "remote.json").read_text())
elif sys.argv[1:3] == ["secrets", "set"]:
    if os.environ.get("MOCK_PUSH_FAIL") == "true":
        sys.exit(5)
    key, filename = sys.argv[3].split("=@", 1)
    remote = json.loads((root / "remote.json").read_text())
    remote = [entry for entry in remote if entry["key"] != key]
    remote.append({"key": key, "value": pathlib.Path(filename).read_text()})
    (root / "remote.json").write_text(json.dumps(remote))
else:
    sys.exit(4)
""")
    remote = scratch / "remote.json"
    remote.write_text("[]")
    provider = scratch / "infra/topf/secrets-provider.sh"
    run([str(provider), "secrets", "get", "development"], environment, expected=1)
    run([str(scratch / "hsctl"), "run", "topf", "--cluster", "development",
         "--init-secrets", "--confirm=false", "secrets"], environment)
    cache = project / "secrets.yaml"
    original = yaml.safe_load(cache.read_text())
    assert json.loads(remote.read_text())[0]["key"] == "SECRETS_YAML"
    cache.chmod(0o644)
    run([str(provider), "secrets", "get", "development"], environment)
    assert cache.stat().st_mode & 0o077 == 0
    print("PASS: Secret cache is readable only by its owner")
    saved_remote = remote.read_text()
    run([str(provider), "secrets", "put", "development"],
        initialization, expected=1, stdin="replacement")
    assert yaml.safe_load(cache.read_text()) == original and remote.read_text() == saved_remote
    print("PASS: Existing cluster secrets cannot be overwritten")
    saved_cache = scratch / "saved-cache"
    cache.rename(saved_cache)
    victim = scratch / "symlink-target"
    victim.write_text("keep-this-file")
    cache.symlink_to(victim)
    run([str(provider), "secrets", "get", "development"], environment, expected=1)
    assert victim.read_text() == "keep-this-file"
    print("PASS: Secret cache rejects symlinks")
    cache.unlink()
    saved_cache.rename(cache)
    remote.write_text(json.dumps([{"key": "SECRETS_YAML", "value": "conflicting-remote-bundle"}]))  # pragma: allowlist secret
    result = run([str(scratch / "hsctl"), "run", "topf", "--cluster", "development",
                  "--refresh-secrets", "render"], environment, expected=1)
    assert yaml.safe_load(cache.read_text()) == original
    assert original["certs"]["os"]["key"] not in result.stderr
    print("PASS: Secret refresh rejects a different cluster CA")
    remote.write_text(saved_remote)
    cache.unlink()
    run([str(scratch / "hsctl"), "run", "topf", "--cluster", "development",
         "render"], environment)
    assert yaml.safe_load(cache.read_text()) == original
    print("PASS: Missing local secrets are restored from Infisical")
    calls = (scratch / "calls").read_text()
    run([str(scratch / "hsctl"), "run", "topf", "--cluster", "development",
         "render"], environment)
    assert (scratch / "calls").read_text() == calls
    assert (project / "output/development-1.yaml").stat().st_mode & 0o077 == 0
    print("PASS: Cached secrets avoid another Infisical request")
    run([str(scratch / "hsctl"), "run", "topf", "--cluster", "development",
         "--refresh-secrets", "render"], environment)
    assert (scratch / "calls").read_text() != calls
    print("PASS: Explicit refresh fetches secrets from Infisical")
    readonly = dict(environment, HSCTL_TOPF_SECRETS_FILE=str(cache))
    calls = (scratch / "calls").read_text()
    run([str(provider), "secrets", "get", "development"], readonly)
    run([str(provider), "secrets", "put", "development"],
        dict(initialization, HSCTL_TOPF_SECRETS_FILE=str(cache)), expected=1, stdin="replacement")
    assert (scratch / "calls").read_text() == calls
    print("PASS: CI credentials cannot overwrite cluster secrets")
    credentials = run([str(scratch / "hsctl"), "run", "topf", "--cluster",
                       "development", "kubeconfig"], environment).stdout
    kubeconfig = yaml.safe_load(credentials)
    certificate = base64.b64decode(kubeconfig["users"][0]["user"]["client-certificate-data"]).decode()
    expiry = run(["openssl", "x509", "-noout", "-enddate"], environment, stdin=certificate).stdout.strip().split("=", 1)[1]
    expiration = datetime.datetime.strptime(expiry, "%b %d %H:%M:%S %Y %Z")
    remaining = expiration - datetime.datetime.now(datetime.UTC).replace(tzinfo=None)
    assert datetime.timedelta(hours=11, minutes=55) < remaining < datetime.timedelta(hours=12, minutes=5)
    assert kubeconfig["clusters"][0]["cluster"]["server"] == "https://10.1.247.21:6443"
    print("PASS: Admin kubeconfig credentials expire after 12 hours")
    if shutil.which("kubectl"):
        user_config = scratch / "user-kubeconfig"
        stale = copy.deepcopy(kubeconfig)
        stale["users"][0]["user"]["client-certificate-data"] = base64.b64encode(b"expired").decode()
        stale["contexts"].append({"name": "unrelated", "context": {"cluster": "unrelated", "user": "unrelated"}})
        user_config.write_text(yaml.safe_dump(stale))
        run([str(scratch / "hsctl"), "get", "kubeconfig", "development", "--break-glass"],
            dict(environment, KUBECONFIG=str(user_config)))
        merged = yaml.safe_load(user_config.read_text())
        assert merged["current-context"] == "topf@development"
        assert any(context["name"] == "unrelated" for context in merged["contexts"])
        assert merged["users"][0]["user"]["client-certificate-data"] not in [base64.b64encode(b"expired").decode(), "DATA+OMITTED"]
        assert user_config.stat().st_mode & 0o077 == 0
        print("PASS: Refreshing admin credentials keeps other kubeconfig contexts")
    cache.unlink()
    remote.write_text(json.dumps([{"key": "TALOSCONFIG", "value": "old-client-config"}]))
    run([str(scratch / "hsctl"), "run", "topf", "--cluster", "development",
         "--init-secrets", "--confirm=false", "secrets"], environment, expected=1)
    assert not cache.exists()
    print("PASS: Incomplete backups cannot initialize a new CA")
    remote.write_text("[]")
    run([str(scratch / "hsctl"), "run", "topf", "--cluster", "development",
         "--init-secrets", "--confirm=false", "secrets"],
        dict(environment, MOCK_PUSH_FAIL="true"), expected=1)
    pending = project / "secrets.pending.yaml"
    pending_bundle = yaml.safe_load(pending.read_text())
    assert not cache.exists()
    run([str(provider), "secrets", "put", "development"],
        initialization, expected=1, stdin="replacement")
    assert yaml.safe_load(pending.read_text()) == pending_bundle
    assert not list(project.glob(".secrets.*"))
    run([str(provider), "secrets", "get", "development"], environment, expected=1)
    run([str(scratch / "hsctl"), "run", "topf", "--cluster", "development",
         "--init-secrets", "--confirm=false", "secrets"], environment)
    assert yaml.safe_load(cache.read_text()) == pending_bundle and not pending.exists()
    print("PASS: Failed secret backups can be retried with the same CA")
    cache.unlink()
    before = (scratch / "calls").read_text().count('"set"')
    run([str(provider), "secrets", "get", "development"],
        dict(environment, MOCK_EXPORT_FAIL="true"), expected=1)
    assert (scratch / "calls").read_text().count('"set"') == before
    assert not any(args[0] in ["folders", "login", "init"] for args in map(json.loads, (scratch / "calls").read_text().splitlines()))
    print("PASS: Failed Infisical reads cannot replace the CA")
    remote.write_text("[]")
    candidates = [yaml.safe_dump(original), yaml.safe_dump(pending_bundle)]

    def initialize(bundle):
        return subprocess.run([str(provider), "secrets", "put", "production"], text=True, input=bundle,
                              env=initialization, capture_output=True, timeout=30)

    with ThreadPoolExecutor(max_workers=2) as executor:
        attempts = list(executor.map(initialize, candidates))
    assert sorted(attempt.returncode for attempt in attempts) == [0, 1]
    winner = candidates[next(index for index, attempt in enumerate(attempts) if attempt.returncode == 0)]
    assert (scratch / "clusters/production/secrets.yaml").read_text() == winner
    assert json.loads(remote.read_text())[0]["value"] == winner
    print("PASS: Concurrent initialization keeps exactly one CA")

    (scratch / "infra/ansible").mkdir()
    shutil.copyfile(REPO / "infra/ansible/requirements.yml", scratch / "infra/ansible/requirements.yml")
    executable(mock_bin / "ansible-galaxy", """#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
assert sys.argv[1:] == ["collection", "install", "-r", str(root / "infra/ansible/requirements.yml")]
(root / "collections-ready").touch()
if os.environ.get("MOCK_COLLECTION_FAIL"):
    sys.exit(6)
""")
    executable(mock_bin / "ansible-playbook", """#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
args = sys.argv[1:]
assert (root / "collections-ready").exists()
assert args[0] == "playbooks/bootstrap-cluster.yml" and "target=development" in args
extra = pathlib.Path(args[args.index("--extra-vars") + 1][1:])
assert extra.stat().st_mode & 0o077 == 0
values = json.loads(extra.read_text())
assert values["hsctl_repo_root"] == str(root)
assert values["hsctl_local"] is True and values["bootstrap_nodes"] == []
assert set(values["hsctl_local_secrets"]) == {"argocd_deploy_key", "infisical_operator"}
(root / "bootstrap-wrapper.json").write_text(json.dumps({"extra_vars_file": str(extra)}))
""")
    calls_before = (scratch / "calls").read_text().splitlines()
    inferred_root = dict(environment)
    inferred_root.pop("HSCTL_REPO_ROOT")
    run([str(scratch / "hsctl"), "run", "bootstrap-cluster", "--cluster", "development", "-e", "local"], inferred_root)
    extra_vars = Path(json.loads((scratch / "bootstrap-wrapper.json").read_text())["extra_vars_file"])
    assert not extra_vars.exists(), "local wrapper must clean its private extra-vars file"
    wrapper_exports = [json.loads(line) for line in (scratch / "calls").read_text().splitlines()[len(calls_before):]]
    assert {arg for call in wrapper_exports for arg in call if arg.startswith("--path=")} == {
        "--path=/k8s/argocd/deploy-key", "--path=/k8s/infisical"}
    print("PASS: Bootstrap finds the checkout and installs collections")
    print("PASS: Bootstrap removes its temporary credentials file")
    (scratch / "bootstrap-wrapper.json").unlink()
    run([str(scratch / "hsctl"), "run", "bootstrap-cluster", "--cluster", "development", "-e", "local"],
        dict(environment, MOCK_COLLECTION_FAIL="true"), expected=6)
    assert not (scratch / "bootstrap-wrapper.json").exists(), "dependency failure must stop before invoking the playbook"
    (mock_bin / "ansible-playbook").unlink()
    print("PASS: Failed collection install stops before Ansible")

    logs = scratch / "bootstrap-calls"
    executable(scratch / "hsctl", """#!/usr/bin/env python3
import json, os, pathlib, sys, yaml
root = pathlib.Path(os.environ["MOCK_ROOT"])
args = sys.argv[1:]
with (root / "bootstrap-calls").open("a") as logfile:
    logfile.write(json.dumps({"tool": "hsctl", "args": args}) + "\\n")
if "render" in args:
    output = pathlib.Path(args[args.index("--output") + 1])
    output.mkdir()
    config = yaml.safe_load((root / "clusters/development/topf.yaml").read_text())
    for node in config["nodes"]:
        (output / (node["host"] + ".yaml")).write_text("machine: {type: controlplane}\\n")
elif "kubeconfig" in args:
    print("private-test-kubeconfig")
""")
    executable(mock_bin / "talosctl", """#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
args = sys.argv[1:]
assert "apply-config" in args and "--insecure" in args
assert pathlib.Path(args[args.index("--file") + 1]).exists()
with (root / "bootstrap-calls").open("a") as logfile:
    logfile.write(json.dumps({"tool": "talosctl", "args": args}) + "\\n")
if os.environ.get("MOCK_APPLY_FAIL") == "true":
    sys.exit(7)
""")
    tasks_dir = scratch / "infra/ansible/tasks"
    tasks_dir.mkdir(parents=True)
    credentials = yaml.safe_load((REPO / "infra/ansible/tasks/cluster-credentials.yml").read_text())
    credentials = [task for task in credentials if task["name"] == "Generate a fresh short-lived admin kubeconfig"]
    (tasks_dir / "cluster-credentials.yml").write_text(yaml.safe_dump(credentials))
    boot_tasks = yaml.safe_load((REPO / "infra/ansible/tasks/bootstrap-talos.yml").read_text())
    boot_tasks = [task for task in boot_tasks if "ansible.builtin.wait_for" not in task]
    (tasks_dir / "bootstrap-talos.yml").write_text(yaml.safe_dump(boot_tasks))
    source = yaml.safe_load((REPO / "infra/ansible/playbooks/bootstrap-cluster.yml").read_text())[0]
    assert [task["ansible.builtin.include_role"]["name"] for task in source["tasks"][0]["block"]
            if "ansible.builtin.include_role" in task] == ["cluster-secrets", "cilium", "argocd"]
    print("PASS: Service order is secrets, Cilium, then ArgoCD")
    source.pop("module_defaults")
    source["hosts"] = "localhost"
    source["vars"].update(hsctl_local=True, talos_cluster_name="development",
                          hsctl_repo_root=str(scratch),
                          bootstrap_nodes=[{"name": "development-1", "dhcp_ip": "192.0.2.40", "static_ip": "10.1.247.21"}])
    source["tasks"][0]["block"] = [task for task in source["tasks"][0]["block"]
                                  if "ansible.builtin.include_tasks" in task or
                                  task["name"] == "Generate a fresh short-lived admin kubeconfig"]
    playbooks = scratch / "infra/ansible/playbooks"
    playbooks.mkdir()
    playbook = playbooks / "bootstrap.yml"
    playbook.write_text(yaml.safe_dump([source]))
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)], environment)
    events = [json.loads(line) for line in logs.read_text().splitlines()]
    apply_event = next(event for event in events if event["tool"] == "talosctl")
    assert apply_event["args"][apply_event["args"].index("--nodes") + 1] == "192.0.2.40"
    print("PASS: Talos config is applied to the DHCP address")
    bootstrap_event = next(event for event in events if "--auto-bootstrap" in event["args"])
    assert re.fullmatch(bootstrap_event["args"][bootstrap_event["args"].index("--nodes-filter") + 1], "development-1")
    assert "--skip-post-apply-checks" in bootstrap_event["args"]
    print("PASS: etcd bootstrap targets only the selected node")
    assert events.index(apply_event) < events.index(bootstrap_event)
    print("PASS: Config apply finishes before etcd bootstrap")
    workspace = Path(next(event["args"][event["args"].index("--output") + 1]
                          for event in events if "render" in event["args"])).parent
    assert not workspace.exists(), "private files must be cleaned after success"
    print("PASS: Successful bootstrap deletes temporary credentials")
    logs.unlink()
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
        dict(environment, MOCK_APPLY_FAIL="true"), expected=2)
    events = [json.loads(line) for line in logs.read_text().splitlines()]
    workspace = Path(next(event["args"][event["args"].index("--output") + 1]
                          for event in events if "render" in event["args"])).parent
    assert not workspace.exists(), "private files must be cleaned after failure"
    assert not any("--auto-bootstrap" in event["args"] for event in events)
    print("PASS: Failed Talos apply stops bootstrap and deletes credentials")
    source["vars"]["bootstrap_nodes"][0]["static_ip"] = "192.0.2.99"
    playbook.write_text(yaml.safe_dump([source]))
    logs.unlink()
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)], environment, expected=2)
    assert not logs.exists(), "bad permanent addresses must fail before secret or node operations"
    print("PASS: Incorrect static IPs stop before any node commands")
