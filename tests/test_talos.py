"""Validate our TOPF-rendered Talos configs and preserved cluster policies."""
import base64
import copy
import ipaddress
import os
import re
import types

import pytest
import yaml

from conftest import REPO

os.umask(0o077)

CLUSTER_NAMES = sorted(p.parent.name for p in (REPO / "clusters").glob("*/topf.yaml"))


def documents(path):
    return [document for document in yaml.safe_load_all(path.read_text()) if document]


def by_kind(config, kind):
    return next(document for document in config if document.get("kind") == kind)


@pytest.fixture(scope="module")
def secrets(tmp_path_factory, run):
    scratch = tmp_path_factory.mktemp("topf-secrets")
    secrets_file = scratch / "secrets.yaml"
    env = dict(os.environ, HSCTL_TOPF_SECRETS_FILE=str(secrets_file), HSCTL_REPO_ROOT=str(REPO))
    run(["talosctl", "gen", "secrets", "-o", str(secrets_file)], env)
    bundle = yaml.safe_load(secrets_file.read_text())
    return types.SimpleNamespace(env=env, bundle=bundle)


@pytest.fixture(scope="module", params=CLUSTER_NAMES)
def cluster(request):
    name = request.param
    config_path = REPO / "clusters" / name / "topf.yaml"
    config = yaml.safe_load(config_path.read_text())
    assert config["clusterName"] == name
    bootstrap = yaml.safe_load((config_path.parent / "apps.yaml").read_text())
    return types.SimpleNamespace(name=name, path=config_path, config=config, bootstrap=bootstrap)


@pytest.fixture(scope="module")
def rendered(cluster, secrets, tmp_path_factory, run):
    effective = copy.deepcopy(cluster.config)
    effective["patchesDir"] = str(REPO / "infra/topf")
    effective["secretsProvider"] = str(REPO / "infra/topf/secrets-provider.sh")
    scratch = tmp_path_factory.mktemp(f"topf-render-{cluster.name}")
    fixture_config = scratch / f"{cluster.name}.yaml"
    fixture_config.write_text(yaml.safe_dump(effective, sort_keys=False))
    output = scratch / cluster.name
    run(["topf", "--topfconfig", str(fixture_config), "render", "--output", str(output)], secrets.env)
    node_subnet = ipaddress.ip_network(cluster.config["data"]["nodeSubnet"])
    return types.SimpleNamespace(effective=effective, output=output, node_subnet=node_subnet,
                                 fixture_config=fixture_config, scratch=scratch)


def test_tailscale_advertises_every_cluster_subnet(cluster):
    directory = next(source["directory"] for source in cluster.bootstrap["spec"]["sources"]
                     if source.get("path") == f"clusters/{cluster.name}")
    assert directory.get("recurse") is True and directory.get("exclude") == "topf.yaml"
    assert not directory.get("include"), "cluster manifests must not be limited to apps.yaml"
    app_values = yaml.safe_load(next(source["helm"]["values"] for source in cluster.bootstrap["spec"]["sources"]
                                     if source.get("path") == "apps"))
    routes = app_values["apps"]["tailscale"]["values"]["subnetRouter"]["advertiseRoutes"]
    assert sorted(routes) == sorted([cluster.config["data"]["nodeSubnet"],
                                     *cluster.config["data"]["podSubnets"], *cluster.config["data"]["serviceSubnets"]])


def test_cluster_declares_secureboot_and_a_valid_schematic(cluster):
    assert cluster.config["secureboot"] is True
    assert re.fullmatch(r"[0-9a-f]{64}", cluster.config["schematicId"])


def test_nodes_have_unique_names_and_addresses_within_the_node_subnet(cluster):
    assert cluster.config["nodes"]
    names = [node["host"] for node in cluster.config["nodes"]]
    addresses = [node["ip"] for node in cluster.config["nodes"]]
    assert len(set(names)) == len(names)
    assert len(set(addresses)) == len(addresses)
    node_subnet = ipaddress.ip_network(cluster.config["data"]["nodeSubnet"])
    for address in addresses:
        assert ipaddress.ip_address(address) in node_subnet


def test_spegel_requires_at_least_three_nodes(cluster):
    assert not cluster.config["data"].get("spegelEnabled") or len(cluster.config["nodes"]) >= 3


def test_pod_and_service_cidrs_do_not_overlap_across_clusters():
    subnets = []
    for name in CLUSTER_NAMES:
        config = yaml.safe_load((REPO / "clusters" / name / "topf.yaml").read_text())
        for key in ["podSubnets", "serviceSubnets"]:
            for subnet in config["data"][key]:
                network = ipaddress.ip_network(subnet)
                assert not any(network.version == seen.version and network.overlaps(seen) for seen in subnets), \
                    f"{name}: {subnet} overlaps another cluster's {key}"
                subnets.append(network)


@pytest.mark.parametrize("setting,empty,message", [
    ("nameservers", [], "declare DNS servers explicitly"),
    ("installDiskMatch", "", "refusing to guess an install disk"),
    ("gateway", "", "declare the default gateway"),
])
@pytest.mark.parametrize("omitted", [True, False])
def test_render_fails_clearly_when_network_settings_are_missing(rendered, secrets, run, setting, empty, message, omitted):
    invalid = copy.deepcopy(rendered.effective)
    invalid["nodes"] = invalid["nodes"][:1]
    invalid["nodes"][0].get("data", {}).pop(setting, None)
    if omitted:
        invalid["data"].pop(setting, None)
    else:
        invalid["data"][setting] = empty
    fixture_config = rendered.scratch / "invalid.yaml"
    fixture_config.write_text(yaml.safe_dump(invalid))
    result = run(["topf", "--topfconfig", str(fixture_config), "render", "--output", str(rendered.scratch / "invalid-out")],
                 secrets.env, expected=1)
    assert message in result.stderr


def test_talosctl_accepts_every_rendered_node_config(rendered, run, secrets):
    for node in rendered.effective["nodes"]:
        run(["talosctl", "validate", "--config", str(rendered.output / f"{node['host']}.yaml"), "--mode", "metal"], secrets.env)


def test_cluster_cas_and_encryption_keys_are_preserved(rendered, secrets):
    bundle = secrets.bundle
    for node in rendered.effective["nodes"]:
        config_docs = documents(rendered.output / f"{node['host']}.yaml")
        legacy = next(document for document in config_docs if "machine" in document)
        assert legacy["machine"]["ca"] == bundle["certs"]["os"]
        assert legacy["cluster"]["etcd"]["ca"] == bundle["certs"]["etcd"]
        assert legacy["machine"]["token"] == bundle["trustdinfo"]["token"]
        assert legacy["cluster"]["token"] == bundle["secrets"]["bootstraptoken"]
        for kind, name in [("KubeAPIServerCAConfig", "k8s"), ("KubeAggregatorCAConfig", "k8saggregator")]:
            issuing = by_kind(config_docs, kind)["issuingCA"]
            assert issuing == {"cert": base64.b64decode(bundle["certs"][name]["crt"]).decode(),
                               "key": base64.b64decode(bundle["certs"][name]["key"]).decode()}
        encryption = by_kind(config_docs, "KubeEtcdEncryptionConfig")["config"]["resources"][0]["providers"][0]
        assert encryption["secretbox"]["keys"][0]["secret"] == bundle["secrets"]["secretboxencryptionsecret"]
        assert by_kind(config_docs, "KubeServiceAccountConfig")["issuer"]["privateKey"] == \
            base64.b64decode(bundle["certs"]["k8sserviceaccount"]["key"]).decode()
        identity = by_kind(config_docs, "DiscoveryIdentityConfig")
        assert identity["clusterID"] == bundle["cluster"]["id"] and identity["clusterSecret"] == bundle["cluster"]["secret"]


def test_node_hostname_and_role_label_match_topf(rendered):
    for node in rendered.effective["nodes"]:
        config_docs = documents(rendered.output / f"{node['host']}.yaml")
        hostname = by_kind(config_docs, "HostnameConfig")
        assert hostname["auto"] == "stable" and not hostname.get("hostname")
        labels = by_kind(config_docs, "KubeNodeConfig")["labels"]
        assert labels["REDACTED/name"] == rendered.effective["clusterName"]
        assert labels["REDACTED/role"] == node["host"]


def test_installer_image_and_disk_match_topf(rendered):
    expected_image = f"factory.talos.dev/metal-installer-secureboot/{rendered.effective['schematicId']}:v{rendered.effective['talosVersion']}"
    for node in rendered.effective["nodes"]:
        config_docs = documents(rendered.output / f"{node['host']}.yaml")
        installation = by_kind(config_docs, "UnattendedInstallConfig")
        assert installation["installer"]["image"] == expected_image
        disk = node.get("data", {}).get("installDiskMatch") or rendered.effective["data"].get("installDiskMatch")
        assert installation["provisioning"]["diskSelector"]["match"] == disk
        assert installation["provisioning"]["wipe"] is False


def test_bond_vlans_and_node_ip_match_topf(rendered):
    for node in rendered.effective["nodes"]:
        config_docs = documents(rendered.output / f"{node['host']}.yaml")
        bond = by_kind(config_docs, "BondConfig")
        assert bond["name"] == "bond1" and bond["links"] == rendered.effective["data"]["bondLinks"]
        assert bond["addresses"] == [{"address": f"{node['ip']}/{rendered.node_subnet.prefixlen}"}]
        assert bond["routes"][0]["gateway"] == rendered.effective["data"]["gateway"]
        assert bond["bondMode"] == "802.3ad" and bond["xmitHashPolicy"] == "layer3+4"
        assert bond["lacpRate"] == "fast" and bond["miimon"] == 100
        for vlan in [241, 271]:
            document = next(d for d in config_docs if d.get("kind") == "VLANConfig" and d["name"] == f"bond1.{vlan}")
            assert document["vlanID"] == vlan and document["parent"] == "bond1"
        assert by_kind(config_docs, "KubeNodeConfig")["nodeIP"]["validSubnets"] == [str(rendered.node_subnet)]


def test_control_plane_only_settings_match_topf(rendered):
    for node in rendered.effective["nodes"]:
        config_docs = documents(rendered.output / f"{node['host']}.yaml")
        assert by_kind(config_docs, "KubeProxyConfig")["enabled"] is False
        assert not any(document.get("kind") == "KubeFlannelCNIConfig" for document in config_docs)
        auth = by_kind(config_docs, "KubeAuthenticationConfig")["configuration"]["jwt"][0]
        assert auth["issuer"]["audiences"] == ["REDACTED"]
        if rendered.effective["data"].get("vip"):
            vip = by_kind(config_docs, "Layer2VIPConfig")
            assert vip["name"] == rendered.effective["data"]["vip"] and vip["link"] == rendered.effective["data"]["vipLink"]
        if rendered.effective["data"].get("longhornEnabled"):
            volume = by_kind(config_docs, "UserVolumeConfig")
            assert volume["name"] == "longhorn" and volume["provisioning"]["minSize"] == "900GiB"
        machine = next(document["machine"] for document in config_docs if "machine" in document)
        spegel = any(entry["path"] == "/var/etc/cri/conf.d/20-spegel.part" for entry in machine.get("files", []))
        assert spegel == bool(rendered.effective["data"].get("spegelEnabled"))


def test_worker_role_omits_control_plane_only_settings(rendered, secrets, run):
    worker = copy.deepcopy(rendered.effective["nodes"][0])
    worker.update(host="validation-worker", role="worker")
    effective = dict(rendered.effective, nodes=[worker])
    fixture_config = rendered.scratch / "worker.yaml"
    fixture_config.write_text(yaml.safe_dump(effective))
    output = rendered.scratch / "worker-output"
    run(["topf", "--topfconfig", str(fixture_config), "render", "--output", str(output)], secrets.env)
    worker_path = output / "validation-worker.yaml"
    run(["talosctl", "validate", "--config", str(worker_path), "--mode", "metal"], secrets.env)
    worker_docs = documents(worker_path)
    assert by_kind(worker_docs, "KubeNodeConfig")["labels"]["REDACTED/role"] == worker["host"]
    assert not any(document.get("kind") in ["KubeAuthenticationConfig", "KubeProxyConfig", "Layer2VIPConfig"]
                   for document in worker_docs)
