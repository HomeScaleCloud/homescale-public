#!/usr/bin/env python3
"""
Ansible dynamic inventory sourced from Omni.

clusters  — Omni-managed clusters via omnictl get clusters
machines  — physical machines via hsctl get machines, sub-grouped by cluster

Requires OMNI_ENDPOINT (or falls back to the default) and
OMNI_SERVICE_ACCOUNT_KEY (or local omniconfig) in the environment.
"""
import json
import os
import re
import shutil
import subprocess
import sys

OMNI_ENDPOINT = os.environ.get("OMNI_ENDPOINT", "https://REDACTED")


def _resolve(name):
    """Return the absolute path of a binary, or abort with a clear error."""
    path = shutil.which(name)
    if not path:
        sys.exit(f"error: '{name}' not found in PATH")
    return path


def _run(cmd):
    """Run a command and return stdout, or None on failure."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            env={**os.environ, "OMNI_ENDPOINT": OMNI_ENDPOINT},
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(f"warning: {' '.join(cmd)} failed: {exc.stderr}\n")
        return None


def _parse_resources(stdout):
    """Parse omnictl/hsctl -o json output.

    Handles single docs, pretty-printed multi-doc sequences (omnictl's actual
    format — multiple JSON objects concatenated with whitespace), and NDJSON.
    Uses raw_decode to stream complete objects rather than splitting on lines,
    which avoids accidentally parsing bare strings from within finalizer arrays.
    """
    if not stdout:
        return []

    decoder = json.JSONDecoder()
    resources = []
    idx = 0
    while idx < len(stdout):
        while idx < len(stdout) and stdout[idx].isspace():
            idx += 1
        if idx >= len(stdout):
            break
        try:
            obj, idx = decoder.raw_decode(stdout, idx)
        except json.JSONDecodeError:
            break
        if isinstance(obj, list):
            resources.extend(o for o in obj if isinstance(o, dict))
        elif isinstance(obj, dict):
            if "metadata" not in obj:
                resources.extend(o for o in obj.get("items", []) if isinstance(o, dict))
            else:
                resources.append(obj)
    return resources


def _group_key(cluster_name):
    return "cluster_" + re.sub(r"[^a-zA-Z0-9_]", "_", cluster_name)


def get_clusters():
    stdout = _run([_resolve("omnictl"), "get", "clusters", "-o", "json"])
    names = []
    for res in _parse_resources(stdout):
        meta = res.get("metadata", {})
        name = meta.get("id") or meta.get("name")
        if name:
            names.append(name)
    return names


def get_machines():
    stdout = _run([_resolve("hsctl"), "get", "machines", "-o", "json"])
    hosts = []
    hostvars = {}

    for res in _parse_resources(stdout):
        if not isinstance(res, dict):
            continue
        meta = res.get("metadata", {})
        spec = res.get("spec", {})
        labels = meta.get("labels", {})

        machine_id = meta.get("id") or meta.get("name")
        hostname = spec.get("network", {}).get("hostname") or machine_id
        if not hostname:
            continue

        # Primary IP — strip CIDR prefix
        addresses = spec.get("network", {}).get("addresses", [])
        primary_ip = addresses[0].split("/")[0] if addresses else None

        cluster = labels.get("omni.sidero.dev/cluster")
        role = "controlplane" if "omni.sidero.dev/role-controlplane" in labels else "worker"

        hosts.append((hostname, cluster))
        hostvars[hostname] = {
            "machine_id": machine_id,
            "omni_cluster": cluster,
            "machine_role": role,
            "machine_platform": labels.get("omni.sidero.dev/platform"),
            **({"ansible_host": primary_ip} if primary_ip else {}),
        }

    return hosts, hostvars


def main():
    if "--host" in sys.argv:
        print(json.dumps({}))
        return

    clusters = get_clusters()
    machines, machine_hostvars = get_machines()

    # Build cluster sub-groups for machines
    cluster_groups = {}
    for hostname, cluster in machines:
        if cluster:
            key = _group_key(cluster)
            cluster_groups.setdefault(key, []).append(hostname)

    inventory = {
        "clusters": {
            "hosts": clusters,
        },
        "machines": {
            "hosts": [h for h, _ in machines],
            "children": list(cluster_groups.keys()),
        },
        **{key: {"hosts": hosts} for key, hosts in cluster_groups.items()},
        "_meta": {"hostvars": machine_hostvars},
    }
    print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
