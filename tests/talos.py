#!/usr/bin/env python3
"""Validate our TOPF-rendered Talos configs and preserved cluster policies."""
import base64
import copy
import ipaddress
import os
from pathlib import Path
import re
import subprocess
import tempfile

import yaml


REPO = Path(__file__).resolve().parents[1]
os.umask(0o077)


def run(command, environment):
    result = subprocess.run(command, env=environment, text=True, capture_output=True, timeout=120)
    if result.returncode:
        raise AssertionError(f"{command[0]} failed: {result.stderr}")
    return result.stdout


def documents(path):
    return [document for document in yaml.safe_load_all(path.read_text()) if document]


def by_kind(config, kind):
    return next(document for document in config if document.get("kind") == kind)


subnets = []
with tempfile.TemporaryDirectory(prefix="topf-validation-") as temporary:
    scratch = Path(temporary)
    environment = dict(os.environ, HSCTL_TOPF_SECRETS_FILE=str(scratch / "secrets.yaml"),
                       HSCTL_REPO_ROOT=str(REPO))
    run(["talosctl", "gen", "secrets", "-o", environment["HSCTL_TOPF_SECRETS_FILE"]], environment)
    bundle = yaml.safe_load(Path(environment["HSCTL_TOPF_SECRETS_FILE"]).read_text())
    for config_path in sorted((REPO / "clusters").glob("*/topf.yaml")):
        config = yaml.safe_load(config_path.read_text())
        assert config["clusterName"] == config_path.parent.name
        bootstrap = yaml.safe_load((config_path.parent / "apps.yaml").read_text())
        directory = next(source["directory"] for source in bootstrap["spec"]["sources"]
                         if source.get("path") == f"clusters/{config['clusterName']}")
        assert directory.get("recurse") is True and directory.get("exclude") == "topf.yaml"
        assert not directory.get("include"), "cluster manifests must not be limited to apps.yaml"
        app_values = yaml.safe_load(next(source["helm"]["values"] for source in bootstrap["spec"]["sources"] if source.get("path") == "apps"))
        routes = app_values["apps"]["tailscale"]["values"]["subnetRouter"]["advertiseRoutes"]
        assert sorted(routes) == sorted([config["data"]["nodeSubnet"], *config["data"]["podSubnets"], *config["data"]["serviceSubnets"]])
        assert config["secureboot"] is True
        assert re.fullmatch(r"[0-9a-f]{64}", config["schematicId"])
        assert config["nodes"]
        names = [node["host"] for node in config["nodes"]]
        addresses = [node["ip"] for node in config["nodes"]]
        assert len(set(names)) == len(names)
        assert len(set(addresses)) == len(addresses)
        node_subnet = ipaddress.ip_network(config["data"]["nodeSubnet"])
        for address in addresses:
            assert ipaddress.ip_address(address) in node_subnet
        for key in ["podSubnets", "serviceSubnets"]:
            for subnet in config["data"][key]:
                network = ipaddress.ip_network(subnet)
                assert not any(network.version == seen.version and network.overlaps(seen) for seen in subnets), "overlapping cluster CIDRs"
                subnets.append(network)
        assert not config["data"].get("spegelEnabled") or len(config["nodes"]) >= 3
        effective = copy.deepcopy(config)
        effective["patchesDir"] = str(REPO / "infra/topf")
        effective["secretsProvider"] = str(REPO / "infra/topf/secrets-provider.sh")
        fixture_config = scratch / f"{config['clusterName']}.yaml"
        fixture_config.write_text(yaml.safe_dump(effective, sort_keys=False))
        output = scratch / config["clusterName"]
        run(["topf", "--topfconfig", str(fixture_config), "render", "--output", str(output)], environment)
        for setting, empty, message in [("nameservers", [], "declare DNS servers explicitly"),
                                        ("installDiskMatch", "", "refusing to guess an install disk"),
                                        ("gateway", "", "declare the default gateway")]:
            for omitted in [True, False]:
                invalid = copy.deepcopy(effective)
                invalid["nodes"] = invalid["nodes"][:1]
                target = invalid["data"]
                invalid["nodes"][0].get("data", {}).pop(setting, None)
                if omitted:
                    target.pop(setting, None)
                else:
                    target[setting] = empty
                fixture_config.write_text(yaml.safe_dump(invalid))
                result = subprocess.run(["topf", "--topfconfig", str(fixture_config), "render", "--output", str(scratch / "invalid")],
                                        env=environment, capture_output=True, text=True, timeout=120)
                assert result.returncode != 0 and message in result.stderr, f"{setting} must fail clearly whether empty or omitted"
            print(f"PASS: {config['clusterName']}: {setting} must be set")
        fixture_config.write_text(yaml.safe_dump(effective))
        expected_image = f"factory.talos.dev/metal-installer-secureboot/{config['schematicId']}:v{config['talosVersion']}"
        for node in effective["nodes"]:
            rendered = output / f"{node['host']}.yaml"
            run(["talosctl", "validate", "--config", str(rendered), "--mode", "metal"], environment)
            print(f"PASS: {node['host']}: talosctl accepts the rendered config")
            config_docs = documents(rendered)
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
            assert by_kind(config_docs, "KubeServiceAccountConfig")["issuer"]["privateKey"] == base64.b64decode(bundle["certs"]["k8sserviceaccount"]["key"]).decode()
            identity = by_kind(config_docs, "DiscoveryIdentityConfig")
            assert identity["clusterID"] == bundle["cluster"]["id"] and identity["clusterSecret"] == bundle["cluster"]["secret"]
            print(f"PASS: {node['host']}: Cluster CAs and encryption keys are preserved")
            hostname = by_kind(config_docs, "HostnameConfig")
            assert hostname["auto"] == "stable" and not hostname.get("hostname")
            labels = by_kind(config_docs, "KubeNodeConfig")["labels"]
            assert labels["REDACTED/name"] == config["clusterName"]
            assert node.get("data", {}).get("nodeRole"), f"{node['host']} must declare data.nodeRole"
            assert labels["REDACTED/role"] == node["data"]["nodeRole"]
            print(f"PASS: {node['host']}: Node role label matches topf.yaml")
            installation = by_kind(config_docs, "UnattendedInstallConfig")
            assert installation["installer"]["image"] == expected_image
            disk = node.get("data", {}).get("installDiskMatch") or effective["data"].get("installDiskMatch")
            assert installation["provisioning"]["diskSelector"]["match"] == disk
            assert installation["provisioning"]["wipe"] is False
            print(f"PASS: {node['host']}: Installer image and disk match topf.yaml")
            bond = by_kind(config_docs, "BondConfig")
            assert bond["name"] == "bond1" and bond["links"] == effective["data"]["bondLinks"]
            assert bond["addresses"] == [{"address": f"{node['ip']}/{node_subnet.prefixlen}"}]
            assert bond["routes"][0]["gateway"] == effective["data"]["gateway"]
            assert bond["bondMode"] == "802.3ad" and bond["xmitHashPolicy"] == "layer3+4"
            assert bond["lacpRate"] == "fast" and bond["miimon"] == 100
            for vlan in [241, 271]:
                document = next(d for d in config_docs if d.get("kind") == "VLANConfig" and d["name"] == f"bond1.{vlan}")
                assert document["vlanID"] == vlan and document["parent"] == "bond1"
            assert by_kind(config_docs, "KubeNodeConfig")["nodeIP"]["validSubnets"] == [str(node_subnet)]
            print(f"PASS: {node['host']}: Bond, VLANs and node IP match topf.yaml")
            assert by_kind(config_docs, "KubeProxyConfig")["enabled"] is False
            assert not any(document.get("kind") == "KubeFlannelCNIConfig" for document in config_docs)
            auth = by_kind(config_docs, "KubeAuthenticationConfig")["configuration"]["jwt"][0]
            assert auth["issuer"]["audiences"] == ["REDACTED"]
            if config["data"].get("vip"):
                vip = by_kind(config_docs, "Layer2VIPConfig")
                assert vip["name"] == config["data"]["vip"] and vip["link"] == config["data"]["vipLink"]
            if config["data"].get("longhornEnabled"):
                volume = by_kind(config_docs, "UserVolumeConfig")
                assert volume["name"] == "longhorn" and volume["provisioning"]["minSize"] == "900GiB"
            machine = next(document["machine"] for document in config_docs if "machine" in document)
            spegel = any(entry["path"] == "/var/etc/cri/conf.d/20-spegel.part" for entry in machine.get("files", []))
            assert spegel == bool(config["data"].get("spegelEnabled"))
        worker = copy.deepcopy(effective["nodes"][0])
        worker.update(host="validation-worker", role="worker")
        effective["nodes"] = [worker]
        fixture_config.write_text(yaml.safe_dump(effective))
        run(["topf", "--topfconfig", str(fixture_config), "render", "--output", str(output)], environment)
        worker_path = output / "validation-worker.yaml"
        run(["talosctl", "validate", "--config", str(worker_path), "--mode", "metal"], environment)
        assert not any(document.get("kind") in ["KubeAuthenticationConfig", "KubeProxyConfig", "Layer2VIPConfig"] for document in documents(worker_path))
        print(f"PASS: {config['clusterName']}: Workers omit OIDC and VIP settings")
