"""Exercise secret recovery and bootstrap-cluster sequencing with mocked services.

Two independent subsystems share one `scratch` checkout (module-scoped, built once):
the Talos CA/secrets lifecycle (secrets-provider.sh + `hsctl run topf`), and the
bootstrap-cluster.yml Ansible sequencing. Tests within each subsystem run in file
order and build on state the previous test left behind, the same way the original
hand-written script did; the two subsystems don't interact with each other.
"""
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
import types

import pytest
import yaml

from conftest import REPO


@pytest.fixture(scope="module")
def scratch(tmp_path_factory, executable):
    root = tmp_path_factory.mktemp("topf-regression")
    shutil.copytree(REPO / "hsctl.d", root / "hsctl.d")
    shutil.copytree(REPO / "infra/topf", root / "infra/topf")
    shutil.copyfile(REPO / "hsctl", root / "hsctl")
    (root / "hsctl").chmod(0o755)
    for cluster in ["development", "production"]:
        project = root / "clusters" / cluster
        project.mkdir(parents=True)
        config = yaml.safe_load((REPO / "clusters" / cluster / "topf.yaml").read_text())
        config["data"]["bootstrapComplete"] = False
        (project / "topf.yaml").write_text(yaml.safe_dump(config))
    mock_bin = root / "bin"
    mock_bin.mkdir()
    environment = dict(os.environ, HSCTL_REPO_ROOT=str(root), MOCK_ROOT=str(root),
                       PATH=str(mock_bin) + os.pathsep + os.environ["PATH"],
                       ANSIBLE_LOCAL_TEMP=str(root / "ansible"))
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
    (root / "remote.json").write_text("[]")
    return types.SimpleNamespace(
        root=root, mock_bin=mock_bin, environment=environment,
        initialization=dict(environment, HSCTL_TOPF_INIT_SECRETS="true"),  # pragma: allowlist secret
        provider=root / "infra/topf/secrets-provider.sh", hsctl=root / "hsctl", remote=root / "remote.json",
        project=root / "clusters/development", cache=root / "clusters/development/secrets.yaml")


# --- Talos CA / secrets lifecycle ---

@pytest.fixture(scope="module")
def initialized_development(scratch, run):
    run([str(scratch.provider), "secrets", "get", "development"], scratch.environment, expected=1)
    run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "--init-secrets", "--confirm=false", "secrets"],
        scratch.environment)
    original = yaml.safe_load(scratch.cache.read_text())
    assert json.loads(scratch.remote.read_text())[0]["key"] == "SECRETS_YAML"
    return original


def test_secret_cache_is_readable_only_by_its_owner(scratch, run, initialized_development):
    scratch.cache.chmod(0o644)
    run([str(scratch.provider), "secrets", "get", "development"], scratch.environment)
    assert scratch.cache.stat().st_mode & 0o077 == 0


def test_existing_cluster_secrets_cannot_be_overwritten(scratch, run, initialized_development):
    saved_remote = scratch.remote.read_text()
    run([str(scratch.provider), "secrets", "put", "development"], scratch.initialization, expected=1, stdin="replacement")
    assert yaml.safe_load(scratch.cache.read_text()) == initialized_development
    assert scratch.remote.read_text() == saved_remote


def test_secret_cache_rejects_symlinks(scratch, run, initialized_development):
    saved_cache = scratch.root / "saved-cache"
    scratch.cache.rename(saved_cache)
    victim = scratch.root / "symlink-target"
    victim.write_text("keep-this-file")
    scratch.cache.symlink_to(victim)
    run([str(scratch.provider), "secrets", "get", "development"], scratch.environment, expected=1)
    assert victim.read_text() == "keep-this-file"
    scratch.cache.unlink()
    saved_cache.rename(scratch.cache)


def test_secret_refresh_rejects_a_different_cluster_ca(scratch, run, initialized_development):
    saved_remote = scratch.remote.read_text()
    scratch.remote.write_text(json.dumps([{"key": "SECRETS_YAML", "value": "conflicting-remote-bundle"}]))  # pragma: allowlist secret
    result = run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "--refresh-secrets", "render"],
                 scratch.environment, expected=1)
    assert yaml.safe_load(scratch.cache.read_text()) == initialized_development
    assert initialized_development["certs"]["os"]["key"] not in result.stderr
    scratch.remote.write_text(saved_remote)


def test_missing_local_secrets_are_restored_from_infisical(scratch, run, initialized_development):
    scratch.cache.unlink()
    run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "render"], scratch.environment)
    assert yaml.safe_load(scratch.cache.read_text()) == initialized_development


def test_cached_secrets_avoid_another_infisical_request(scratch, run):
    calls_before = (scratch.root / "calls").read_text()
    run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "render"], scratch.environment)
    assert (scratch.root / "calls").read_text() == calls_before
    assert (scratch.project / "output/development-1.yaml").stat().st_mode & 0o077 == 0


def test_explicit_refresh_fetches_secrets_from_infisical(scratch, run):
    calls_before = (scratch.root / "calls").read_text()
    run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "--refresh-secrets", "render"], scratch.environment)
    assert (scratch.root / "calls").read_text() != calls_before


def test_ci_credentials_cannot_overwrite_cluster_secrets(scratch, run):
    readonly = dict(scratch.environment, HSCTL_TOPF_SECRETS_FILE=str(scratch.cache))
    calls_before = (scratch.root / "calls").read_text()
    run([str(scratch.provider), "secrets", "get", "development"], readonly)
    run([str(scratch.provider), "secrets", "put", "development"],
        dict(scratch.initialization, HSCTL_TOPF_SECRETS_FILE=str(scratch.cache)), expected=1, stdin="replacement")
    assert (scratch.root / "calls").read_text() == calls_before


@pytest.fixture(scope="module")
def admin_kubeconfig(scratch, run):
    credentials = run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "kubeconfig"], scratch.environment).stdout
    return yaml.safe_load(credentials)


def test_admin_kubeconfig_credentials_expire_after_12_hours(scratch, run, admin_kubeconfig):
    certificate = base64.b64decode(admin_kubeconfig["users"][0]["user"]["client-certificate-data"]).decode()
    expiry = run(["openssl", "x509", "-noout", "-enddate"], scratch.environment, stdin=certificate).stdout.strip().split("=", 1)[1]
    expiration = datetime.datetime.strptime(expiry, "%b %d %H:%M:%S %Y %Z")
    remaining = expiration - datetime.datetime.now(datetime.UTC).replace(tzinfo=None)
    assert datetime.timedelta(hours=11, minutes=55) < remaining < datetime.timedelta(hours=12, minutes=5)
    assert admin_kubeconfig["clusters"][0]["cluster"]["server"] == "https://10.1.247.21:6443"


@pytest.mark.skipif(not shutil.which("kubectl"), reason="requires a local kubectl binary")
def test_refreshing_admin_credentials_keeps_other_kubeconfig_contexts(scratch, run, admin_kubeconfig):
    user_config = scratch.root / "user-kubeconfig"
    stale = copy.deepcopy(admin_kubeconfig)
    stale["users"][0]["user"]["client-certificate-data"] = base64.b64encode(b"expired").decode()
    stale["contexts"].append({"name": "unrelated", "context": {"cluster": "unrelated", "user": "unrelated"}})
    user_config.write_text(yaml.safe_dump(stale))
    run([str(scratch.hsctl), "get", "kubeconfig", "development", "--break-glass"], dict(scratch.environment, KUBECONFIG=str(user_config)))
    merged = yaml.safe_load(user_config.read_text())
    assert merged["current-context"] == "topf@development"
    assert any(context["name"] == "unrelated" for context in merged["contexts"])
    assert merged["users"][0]["user"]["client-certificate-data"] not in [base64.b64encode(b"expired").decode(), "DATA+OMITTED"]
    assert user_config.stat().st_mode & 0o077 == 0


def test_incomplete_backups_cannot_initialize_a_new_ca(scratch, run):
    scratch.cache.unlink()
    scratch.remote.write_text(json.dumps([{"key": "TALOSCONFIG", "value": "old-client-config"}]))  # pragma: allowlist secret
    run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "--init-secrets", "--confirm=false", "secrets"],
        scratch.environment, expected=1)
    assert not scratch.cache.exists()
    scratch.remote.write_text("[]")


@pytest.fixture(scope="module")
def pending_bundle_after_push_failure(scratch, run):
    run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "--init-secrets", "--confirm=false", "secrets"],
        dict(scratch.environment, MOCK_PUSH_FAIL="true"), expected=1)
    return yaml.safe_load((scratch.project / "secrets.pending.yaml").read_text())


def test_failed_secret_backup_leaves_a_pending_bundle_not_the_cache(scratch, pending_bundle_after_push_failure):
    assert not scratch.cache.exists()


def test_initialization_cannot_proceed_while_a_backup_is_pending(scratch, run, pending_bundle_after_push_failure):
    pending = scratch.project / "secrets.pending.yaml"
    run([str(scratch.provider), "secrets", "put", "development"], scratch.initialization, expected=1, stdin="replacement")
    assert yaml.safe_load(pending.read_text()) == pending_bundle_after_push_failure
    assert not list(scratch.project.glob(".secrets.*"))
    run([str(scratch.provider), "secrets", "get", "development"], scratch.environment, expected=1)


def test_retrying_init_secrets_reuses_the_pending_bundle(scratch, run, pending_bundle_after_push_failure):
    pending = scratch.project / "secrets.pending.yaml"
    run([str(scratch.hsctl), "run", "topf", "--cluster", "development", "--init-secrets", "--confirm=false", "secrets"],
        scratch.environment)
    assert yaml.safe_load(scratch.cache.read_text()) == pending_bundle_after_push_failure and not pending.exists()


def test_failed_infisical_reads_cannot_replace_the_ca(scratch, run):
    scratch.cache.unlink()
    sets_before = (scratch.root / "calls").read_text().count('"set"')
    run([str(scratch.provider), "secrets", "get", "development"], dict(scratch.environment, MOCK_EXPORT_FAIL="true"), expected=1)
    assert (scratch.root / "calls").read_text().count('"set"') == sets_before
    assert not any(args[0] in ["folders", "login", "init"] for args in map(json.loads, (scratch.root / "calls").read_text().splitlines()))


def test_concurrent_initialization_keeps_exactly_one_ca(scratch, initialized_development, pending_bundle_after_push_failure):
    scratch.remote.write_text("[]")
    candidates = [yaml.safe_dump(initialized_development), yaml.safe_dump(pending_bundle_after_push_failure)]

    def initialize(bundle):
        return subprocess.run([str(scratch.provider), "secrets", "put", "production"], text=True, input=bundle,
                              env=scratch.initialization, capture_output=True, timeout=30)

    with ThreadPoolExecutor(max_workers=2) as executor:
        attempts = list(executor.map(initialize, candidates))
    assert sorted(attempt.returncode for attempt in attempts) == [0, 1]
    winner = candidates[next(index for index, attempt in enumerate(attempts) if attempt.returncode == 0)]
    assert (scratch.root / "clusters/production/secrets.yaml").read_text() == winner
    assert json.loads(scratch.remote.read_text())[0]["value"] == winner


# --- bootstrap-cluster.yml sequencing ---

@pytest.fixture(scope="module")
def raw_bootstrap_playbook():
    return yaml.safe_load((REPO / "infra/ansible/playbooks/bootstrap-cluster.yml").read_text())[0]


def test_service_order_is_secrets_cilium_then_argocd(raw_bootstrap_playbook):
    names = [task["ansible.builtin.include_role"]["name"] for task in raw_bootstrap_playbook["tasks"][0]["block"]
             if "ansible.builtin.include_role" in task]
    assert names == ["cluster-secrets", "cilium", "argocd"]


@pytest.fixture
def collections_bin(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    return bin_dir


@pytest.fixture(scope="module")
def ansible_requirements(scratch):
    (scratch.root / "infra/ansible").mkdir(exist_ok=True, parents=True)
    shutil.copyfile(REPO / "infra/ansible/requirements.yml", scratch.root / "infra/ansible/requirements.yml")


def test_bootstrap_finds_the_checkout_installs_collections_and_cleans_up(scratch, run, executable, ansible_requirements, collections_bin):
    executable(collections_bin / "ansible-galaxy", """#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
assert sys.argv[1:] == ["collection", "install", "-r", str(root / "infra/ansible/requirements.yml")]
(root / "collections-ready").touch()
""")
    executable(collections_bin / "ansible-playbook", """#!/usr/bin/env python3
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
    env = dict(scratch.environment, PATH=str(collections_bin) + os.pathsep + scratch.environment["PATH"])
    env.pop("HSCTL_REPO_ROOT")
    calls_before = (scratch.root / "calls").read_text().splitlines()
    run([str(scratch.hsctl), "run", "bootstrap-cluster", "--cluster", "development", "-e", "local"], env)
    extra_vars = Path(json.loads((scratch.root / "bootstrap-wrapper.json").read_text())["extra_vars_file"])
    assert not extra_vars.exists(), "local wrapper must clean its private extra-vars file"
    wrapper_exports = [json.loads(line) for line in (scratch.root / "calls").read_text().splitlines()[len(calls_before):]]
    assert {arg for call in wrapper_exports for arg in call if arg.startswith("--path=")} == {
        "--path=/k8s/argocd/deploy-key", "--path=/k8s/infisical"}
    (scratch.root / "bootstrap-wrapper.json").unlink()


def test_failed_collection_install_stops_before_ansible(scratch, run, executable, ansible_requirements, collections_bin):
    executable(collections_bin / "ansible-galaxy", """#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
assert sys.argv[1:] == ["collection", "install", "-r", str(root / "infra/ansible/requirements.yml")]
sys.exit(6)
""")
    env = dict(scratch.environment, PATH=str(collections_bin) + os.pathsep + scratch.environment["PATH"])
    run([str(scratch.hsctl), "run", "bootstrap-cluster", "--cluster", "development", "-e", "local"],
        dict(env, MOCK_COLLECTION_FAIL="true"), expected=6)
    assert not (scratch.root / "bootstrap-wrapper.json").exists(), "dependency failure must stop before invoking the playbook"


@pytest.fixture(scope="module")
def sequencing(scratch, executable, raw_bootstrap_playbook):
    """Build a trimmed single-play copy of bootstrap-cluster.yml that runs locally against
    mocked hsctl/talosctl, skipping ansible's own wait_for/retry delays."""
    executable(scratch.root / "hsctl", """#!/usr/bin/env python3
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
elif "--auto-bootstrap" in args:
    attempts = sum("--auto-bootstrap" in json.loads(line)["args"]
                   for line in (root / "bootstrap-calls").read_text().splitlines())
    failure = os.environ.get("MOCK_BOOTSTRAP_CONNECTION_FAIL")
    if failure == "always" or (failure == "once" and attempts == 1):
        print("failed to create client: connect: connection refused", file=sys.stderr)
        sys.exit(1)
""")
    executable(scratch.mock_bin / "talosctl", """#!/usr/bin/env python3
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
    tasks_dir = scratch.root / "infra/ansible/tasks"
    tasks_dir.mkdir(parents=True, exist_ok=True)
    credentials = yaml.safe_load((REPO / "infra/ansible/tasks/cluster-credentials.yml").read_text())
    credentials = [task for task in credentials if task["name"] == "Generate a fresh short-lived admin kubeconfig"]
    (tasks_dir / "cluster-credentials.yml").write_text(yaml.safe_dump(credentials))

    def fast_tasks(tasks):
        result = []
        for task in tasks:
            if "ansible.builtin.wait_for" in task:
                continue
            if "block" in task:
                task["block"] = fast_tasks(task["block"])
            if "retries" in task:
                task.update(retries=min(task["retries"], 2), delay=0)
            result.append(task)
        return result

    boot_tasks = fast_tasks(yaml.safe_load((REPO / "infra/ansible/tasks/bootstrap-talos.yml").read_text()))
    (tasks_dir / "bootstrap-talos.yml").write_text(yaml.safe_dump(boot_tasks))

    base = copy.deepcopy(raw_bootstrap_playbook)
    base.pop("module_defaults")
    base["hosts"] = "localhost"
    tasks = []
    for task in base["tasks"][0]["block"]:
        if "ansible.builtin.include_tasks" in task:
            tasks.append(task)
        elif task["name"] == "Wait for the Kubernetes API to respond":
            tasks.append({"name": task["name"], "ansible.builtin.command": {"argv": [str(scratch.root / "hsctl"), "test-api-probe"]}})
    base["tasks"][0]["block"] = tasks

    playbooks_dir = scratch.root / "infra/ansible/playbooks"
    playbooks_dir.mkdir(exist_ok=True)
    playbook_path = playbooks_dir / "bootstrap.yml"
    logs = scratch.root / "bootstrap-calls"
    workspace_record = scratch.root / "bootstrap-workspace"

    def write(vars_overrides, record_workspace=True):
        play = copy.deepcopy(base)
        play["vars"].update(vars_overrides)
        if record_workspace:
            play["pre_tasks"].append({"name": "Record the test workspace", "ansible.builtin.copy": {
                "content": "{{ _bootstrap_workspace.path }}", "dest": str(workspace_record)}})
        playbook_path.write_text(yaml.safe_dump([play]))
        logs.unlink(missing_ok=True)
        workspace_record.unlink(missing_ok=True)

    def events():
        return [json.loads(line) for line in logs.read_text().splitlines()] if logs.exists() else []

    return types.SimpleNamespace(write=write, events=events, playbook=playbook_path, workspace_record=workspace_record)


def base_vars(**overrides):
    vars_ = dict(hsctl_local=True, talos_cluster_name="development",
                bootstrap_nodes=[{"name": "development-1", "dhcp_ip": "192.0.2.40", "static_ip": "10.1.247.21"}])
    vars_.update(overrides)
    return vars_


def run_sequencing(scratch, run, sequencing, vars_overrides, expected=0, record_workspace=True, env_overrides=None):
    sequencing.write(base_vars(hsctl_repo_root=str(scratch.root), **vars_overrides), record_workspace=record_workspace)
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(sequencing.playbook)],
        dict(scratch.environment, **(env_overrides or {})), expected=expected)
    return sequencing.events()


def test_successful_bootstrap_applies_then_bootstraps_etcd_then_checks_the_api(scratch, run, sequencing):
    events = run_sequencing(scratch, run, sequencing, {})
    apply_event = next(event for event in events if event["tool"] == "talosctl")
    assert apply_event["args"][apply_event["args"].index("--nodes") + 1] == "192.0.2.40", \
        "Talos config must apply to the DHCP address, not the permanent one"
    bootstrap_event = next(event for event in events if "--auto-bootstrap" in event["args"])
    assert re.fullmatch(bootstrap_event["args"][bootstrap_event["args"].index("--nodes-filter") + 1], "development-1")
    assert "--skip-post-apply-checks" in bootstrap_event["args"]
    assert events.index(apply_event) < events.index(bootstrap_event), "config apply must finish before etcd bootstrap"
    kubeconfig_event = next(event for event in events if "kubeconfig" in event["args"])
    api_event = next(event for event in events if "test-api-probe" in event["args"])
    assert events.index(bootstrap_event) < events.index(kubeconfig_event) < events.index(api_event)
    workspace = Path(next(event["args"][event["args"].index("--output") + 1] for event in events if "render" in event["args"])).parent
    assert not workspace.exists(), "private files must be cleaned up after a successful bootstrap"


def test_bootstrap_retries_a_connection_failure_without_reinstalling(scratch, run, sequencing):
    events = run_sequencing(scratch, run, sequencing, {}, env_overrides={"MOCK_BOOTSTRAP_CONNECTION_FAIL": "once"})
    assert sum("--auto-bootstrap" in event["args"] for event in events) == 2
    assert sum(event["tool"] == "talosctl" for event in events) == 1
    workspace = Path(next(event["args"][event["args"].index("--output") + 1] for event in events if "render" in event["args"])).parent
    assert not workspace.exists()


def test_repeated_connection_failures_stop_setup_and_delete_credentials(scratch, run, sequencing):
    events = run_sequencing(scratch, run, sequencing, {}, expected=2, env_overrides={"MOCK_BOOTSTRAP_CONNECTION_FAIL": "always"})
    assert sum("--auto-bootstrap" in event["args"] for event in events) > 1
    assert sum(event["tool"] == "talosctl" for event in events) == 1
    assert not any("kubeconfig" in event["args"] for event in events)
    workspace = Path(next(event["args"][event["args"].index("--output") + 1] for event in events if "render" in event["args"])).parent
    assert not workspace.exists()


def test_bootstrap_without_explicit_nodes_retries_etcd_on_the_first_control_plane(scratch, run, sequencing):
    config = yaml.safe_load((scratch.project / "topf.yaml").read_text())
    config["nodes"].insert(0, {"host": "development-worker", "ip": "192.0.2.41", "role": "worker"})
    (scratch.project / "topf.yaml").write_text(yaml.safe_dump(config))

    sequencing.write(base_vars(hsctl_repo_root=str(scratch.root), bootstrap_nodes=None))
    play = yaml.safe_load(sequencing.playbook.read_text())
    play[0]["vars"].pop("bootstrap_nodes")
    sequencing.playbook.write_text(yaml.safe_dump(play))
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(sequencing.playbook)],
        dict(scratch.environment, MOCK_BOOTSTRAP_CONNECTION_FAIL="once"))
    events = sequencing.events()

    bootstraps = [event for event in events if "--auto-bootstrap" in event["args"]]
    assert len(bootstraps) == 2
    assert all(re.fullmatch(event["args"][event["args"].index("--nodes-filter") + 1], "development-1") for event in bootstraps)
    assert not any(event["tool"] == "talosctl" or "--init-secrets" in event["args"] or "render" in event["args"] for event in events)
    kubeconfig_event = next(event for event in events if "kubeconfig" in event["args"])
    api_event = next(event for event in events if "test-api-probe" in event["args"])
    assert events.index(bootstraps[-1]) < events.index(kubeconfig_event) < events.index(api_event)
    assert not sequencing.workspace_record.exists() or not Path(sequencing.workspace_record.read_text()).exists()


def test_failed_etcd_bootstrap_stops_before_the_api_check_and_removes_private_files(scratch, run, sequencing):
    events = run_sequencing(scratch, run, sequencing, {"bootstrap_nodes": []}, expected=2,
                            env_overrides={"MOCK_BOOTSTRAP_CONNECTION_FAIL": "always"})
    assert sum("--auto-bootstrap" in event["args"] for event in events) > 1
    assert not any("kubeconfig" in event["args"] or "test-api-probe" in event["args"] for event in events)
    assert not sequencing.workspace_record.exists() or not Path(sequencing.workspace_record.read_text()).exists()


def test_ci_bootstrap_skips_node_install_and_etcd_bootstrap(scratch, run, sequencing):
    events = run_sequencing(scratch, run, sequencing, {"hsctl_local": False})
    assert [event["args"][-1] for event in events] == ["kubeconfig", "test-api-probe"]
    assert not sequencing.workspace_record.exists() or not Path(sequencing.workspace_record.read_text()).exists()


def test_failed_talos_apply_stops_bootstrap_and_deletes_credentials(scratch, run, sequencing):
    events = run_sequencing(scratch, run, sequencing, {}, expected=2, env_overrides={"MOCK_APPLY_FAIL": "true"})
    workspace = Path(next(event["args"][event["args"].index("--output") + 1] for event in events if "render" in event["args"])).parent
    assert not workspace.exists(), "private files must be cleaned up after a failed apply"
    assert not any("--auto-bootstrap" in event["args"] for event in events)


def test_incorrect_static_ips_stop_before_any_node_commands(scratch, run, sequencing):
    nodes = [{"name": "development-1", "dhcp_ip": "192.0.2.40", "static_ip": "192.0.2.99"}]
    events = run_sequencing(scratch, run, sequencing, {"bootstrap_nodes": nodes}, expected=2)
    assert not events, "bad permanent addresses must fail before secret or node operations"


def test_completed_clusters_skip_bootstrap(scratch, run, sequencing):
    config = yaml.safe_load((scratch.project / "topf.yaml").read_text())
    config["data"]["bootstrapComplete"] = True
    (scratch.project / "topf.yaml").write_text(yaml.safe_dump(config))
    events = run_sequencing(scratch, run, sequencing, {})
    assert not events, "completed clusters must skip bootstrap before any node or credential commands"


# --- cluster-secrets role, mocking only its external module boundaries ---

@pytest.fixture(scope="module")
def service_credentials_environment(scratch, executable):
    collection_root = scratch.root / "collections/ansible_collections"
    module_header = '''from ansible.module_utils.basic import AnsibleModule
import json, os, pathlib
root = pathlib.Path(os.environ["MOCK_ROOT"])
'''
    modules = {
        ("infisical/vault", "login"): '''module = AnsibleModule(argument_spec={})
module.fail_json(msg="Bootstrap must reuse the cluster credentials login")
''',
        ("infisical/vault", "read_secrets"): '''module = AnsibleModule(argument_spec={"login_data": dict(type="dict"), "project_id": {}, "env_slug": {}, "path": {}, "as_dict": dict(type="bool")})
assert module.params["login_data"] == {"session": "existing"}
assert module.params["env_slug"] == "prod"
key = {"/k8s/argocd/deploy-key": "argocd_deploy_key", "/k8s/infisical": "infisical_operator"}[module.params["path"]]
module.exit_json(changed=False, secrets=json.loads((root / "service-secrets.json").read_text())[key])
''',
        ("kubernetes/core", "k8s"): '''module = AnsibleModule(argument_spec={"state": {}, "api_version": {}, "kind": {}, "name": {}, "definition": dict(type="dict")})
assert module.params["state"] == "present"
with (root / "service-objects.jsonl").open("a") as stream:
    stream.write(json.dumps(module.params) + "\\n")
module.exit_json(changed=False)
''',
    }
    for (collection, name), code in modules.items():
        directory = collection_root / collection / "plugins/modules"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / (name + ".py")).write_text(module_header + code)
    return dict(scratch.environment, ANSIBLE_COLLECTIONS_PATH=str(collection_root.parent),
               ANSIBLE_ROLES_PATH=str(REPO / "infra/ansible/roles"))


@pytest.mark.parametrize("local", [False, True])
def test_cluster_secrets_role_reconciles_service_credentials_without_logging_them(scratch, run, executable, service_credentials_environment, local):
    credentials = {"argocd_deploy_key": {"sshPrivateKey": "private-test-deploy-key-" + str(local)},  # pragma: allowlist secret
                   "infisical_operator": {"INFISICAL_OPERATOR_CLIENT_ID": "test-client",
                                          "INFISICAL_OPERATOR_CLIENT_SECRET": "private-test-operator-" + str(local)}}  # pragma: allowlist secret
    (scratch.root / "service-secrets.json").write_text(json.dumps(credentials))
    play = {"hosts": "localhost", "gather_facts": False,
           "vars": {"hsctl_local": local, "hsctl_local_secrets": credentials, "_infisical": {"login_data": {"session": "existing"}}},
           "roles": ["cluster-secrets"]}
    playbook = scratch.root / "infra/ansible/playbooks/service-credentials.yml"
    playbook.write_text(yaml.safe_dump([play]))
    objects_log = scratch.root / "service-objects.jsonl"
    objects_log.write_text("")

    result = run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)], service_credentials_environment)
    objects = [json.loads(line) for line in objects_log.read_text().splitlines()]
    assert [obj["name"] for obj in objects if obj["kind"] == "Namespace"] == ["argocd", "infisical"]
    secrets = {obj["definition"]["metadata"]["name"]: obj["definition"]["stringData"]
               for obj in objects if obj["definition"]}
    assert secrets["homescale-k8s-deploy-key"]["sshPrivateKey"] == credentials["argocd_deploy_key"]["sshPrivateKey"]
    assert secrets["infisical-operator-auth"]["clientSecret"] == credentials["infisical_operator"]["INFISICAL_OPERATOR_CLIENT_SECRET"]
    assert "private-test-" not in result.stdout
