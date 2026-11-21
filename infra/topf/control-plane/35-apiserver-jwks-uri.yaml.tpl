{{- if get .Data "vip" }}
cluster:
  apiServer:
    extraArgs:
      service-account-jwks-uri: "https://{{ .Data.vip }}:6443/openid/v1/jwks"
{{- end }}
