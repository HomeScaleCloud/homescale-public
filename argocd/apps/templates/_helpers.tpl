{{/*
Build an Application name that stays unique in a single Argo CD instance.
*/}}
{{- define "homescale-apps.applicationName" -}}
{{- $root := index . "root" -}}
{{- $appName := index . "appName" -}}
{{- $prefix := default $root.Values.cluster.name $root.Values.applicationNamePrefix -}}
{{- if $prefix -}}
{{- printf "%s-%s" $prefix $appName | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $appName | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
