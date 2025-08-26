{{- define "argocd.application" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  labels:
    app.homescale.cloud/managed: true
spec:
  project: {{ default $.Values.global.project .app.project }}
  source:
    repoURL: {{ default $.Values.global.repoURL .app.repoURL }}
    chart: {{ .name }}
    targetRevision: {{ default "latest" .app.targetRevision }}
    helm:
      values: |
{{ toYaml .app.values | indent 8 }}
  destination:
    server: {{ default $.Values.global.destination.server .app.destination.server }}
    namespace: {{ .app.destination.namespace }}
  syncPolicy:
{{ toYaml (default $.Values.global.syncPolicy .app.syncPolicy) | indent 4 }}
{{- end -}}
