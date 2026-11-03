{{- $disk := get .Node.Data "installDiskMatch" | default (get .Data "installDiskMatch") }}
{{- if not $disk }}{{ fail (printf "%s needs data.installDiskMatch; refusing to guess an install disk" .Node.Host) }}{{ end }}
apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: {{ $disk | quote }}
