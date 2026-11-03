{{- if get .Data "vip" }}
apiVersion: v1alpha1
kind: Layer2VIPConfig
name: {{ .Data.vip | quote }}
link: {{ .Data.vipLink }}
{{- end }}
