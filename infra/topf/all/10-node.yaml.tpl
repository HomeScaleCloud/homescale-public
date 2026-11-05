apiVersion: v1alpha1
kind: HostnameConfig
auto: stable
---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  REDACTED/name: {{ .ClusterName | quote }}
  REDACTED/role: {{ .Node.Host | quote }}
nodeIP:
  validSubnets:
    - {{ .Data.nodeSubnet }}
