apiVersion: v1alpha1
kind: HostnameConfig
auto: stable
---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  REDACTED/name: {{ .ClusterName | quote }}
  {{- with (get .Node.Data "nodeRole") }}
  REDACTED/role: {{ . | quote }}
  {{- end }}
nodeIP:
  validSubnets:
    - {{ .Data.nodeSubnet }}
