{{- if get .Data "vip" }}
apiVersion: v1alpha1
kind: KubeAPIServerConfig
image: registry.k8s.io/kube-apiserver:v1.37.2
extraArgs:
    service-account-jwks-uri: "https://{{ .Data.vip }}:6443/openid/v1/jwks"
{{- end }}
