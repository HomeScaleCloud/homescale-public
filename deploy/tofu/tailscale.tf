resource "tailscale_acl" "acl" {
  acl = <<EOF
    // This tailnet's ACLs are maintained in https://github.com/HomeScaleCloud/homescale
    {
      "groups": {
        "group:lon1-core-admin": [
          "m4xmorris@github",
          "nanni237@github"
        ],
        "group:boa1-prod-admin": [
          "nanni237@github"
        ]
      },
      "acls": [
        {
          "action": "accept",
          "src": ["group:lon1-core-admin"],
          "dst": ["tag:admin-app-lon1-core:*"],
          "srcPosture": ["posture:linux", "posture:macos", "posture:windows"]
        },
        {
          "action": "accept",
          "src": ["group:boa1-prod-admin"],
          "dst": ["tag:boa1-prod-admin-app:*"],
          "srcPosture": ["posture:linux", "posture:macos", "posture:windows"]
        },
        {
          "action": "accept",
          "src": ["group:lon1-core-admin"],
          "dst": ["tag:app-lon1-core:*"]
        },
        {
          "action": "accept",
          "src": ["tag:boa1-prod-router"],
          "dst": ["tag:admin-app-lon1-core"]
        },
        {
          "action": "accept",
          "src": ["group:boa1-prod-admin"],
          "dst": ["tag:boa1-prod-app:*"]
        },
        {
          "action": "accept",
          "src": ["tag:github-actions"],
          "dst": [
            "tag:admin-app-lon1-core:443",
          ]
        }

      ],
      "tagOwners": {
        "tag:k8s-operator": [],
        "tag:app-lon1-core": ["tag:k8s-operator"],
        "tag:admin-app-lon1-core": ["tag:k8s-operator"],
        "tag:boa1-prod-router": [],
        "tag:boa1-prod-app": ["tag:k8s-operator"],
        "tag:boa1-prod-admin-app": ["tag:k8s-operator"],
        "tag:github-actions": []
      },
      "postures": {
        "posture:tsVersion": ["node:tsVersion >= '1.80.2'"],
        "posture:linux": ["node:os == 'linux'"],
        "posture:macos": ["node:os == 'macos'", "node:osVersion >= '15.3.2'"],
        "posture:windows": ["node:os == 'windows'", "node:osVersion >= '10.0.26100.3476'"],
        "posture:ios": ["node:os == 'ios'", "node:osVersion >= '18.3.2'"]
      },
      "defaultSrcPosture": [
        "posture:tsVersion",
        "posture:linux",
        "posture:macos",
        "posture:windows",
        "posture:ios"
      ],
      "nodeAttrs": [
        {
          "target": ["autogroup:member"],
          "attr": ["mullvad"]
        }
      ]
    }
  EOF
}
