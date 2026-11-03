{{- if not (get .Data "gateway") }}{{ fail "declare the default gateway in data.gateway" }}{{ end }}
{{- $nameservers := get .Node.Data "nameservers" | default (get .Data "nameservers") }}
{{- if not $nameservers }}{{ fail "declare DNS servers explicitly in data.nameservers" }}{{ end }}
apiVersion: v1alpha1
kind: BondConfig
name: bond1
links: {{ toPrettyJson .Data.bondLinks }}
bondMode: 802.3ad
xmitHashPolicy: layer3+4
lacpRate: fast
miimon: 100
addresses:
  - address: {{ .Node.IP }}/{{ last (splitList "/" .Data.nodeSubnet) }}
routes:
  - gateway: {{ .Data.gateway }}
---
apiVersion: v1alpha1
kind: VLANConfig
name: bond1.241
vlanID: 241
parent: bond1
---
apiVersion: v1alpha1
kind: VLANConfig
name: bond1.271
vlanID: 271
parent: bond1
---
apiVersion: v1alpha1
kind: ResolverConfig
nameservers:
  {{- range $nameservers }}
  - address: {{ . | quote }}
  {{- end }}
