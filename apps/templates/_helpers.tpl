{{/*
Build an Application name unique within a single ArgoCD instance.
*/}}
{{- define "homescale-catalog.applicationName" -}}
{{- $root := index . "root" -}}
{{- $appName := index . "appName" -}}
{{- $prefix := $root.Values.applicationNamePrefix -}}
{{- if $prefix -}}
{{- printf "%s-%s" $prefix $appName | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $appName | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
