{{/*
Shared jobTemplate.spec.template for automatron's CronJobs. Call with:
  include "automatron.podTemplate" (dict "root" $ "playbook" "bootstrap-cluster" "chainNext" "automatron-bootstrap-cluster")
"chainNext" (optional) sets CHAIN_NEXT_CRONJOB so this run triggers that CronJob's jobTemplate on success.
*/}}
{{- define "automatron.podTemplate" -}}
{{- $root := .root -}}
metadata:
  labels:
    app: automatron
spec:
  serviceAccountName: automatron
  restartPolicy: Never
  volumes:
    - name: repo
      emptyDir: {}
    - name: hosts
      emptyDir: {}
    - name: git-ssh-key
      secret:
        secretName: automatron-secrets
        items:
          - key: GIT_DEPLOY_KEY
            path: sshPrivateKey
            mode: 0600
    - name: git-ssh-key-fixed
      emptyDir: {}
  initContainers:
    # Resolves REDACTED / REDACTED to their
    # real in-cluster ClusterIPs and writes a corrected /etc/hosts to a shared volume,
    # so automatron reaches Omni in-cluster while keeping the real hostnames (and TLS
    # cert validation) unchanged. Done at pod start rather than via Helm's `lookup`,
    # which ArgoCD's renders have been observed returning empty for.
    - name: omni-hosts
      image: "{{ $root.Values.automatron.image.repository }}:{{ $root.Values.automatron.image.tag }}"
      command: ["sh", "-c"]
      args:
        - |
          set -e
          cp /etc/hosts /shared/hosts
          echo "$(kubectl get svc api -n omni -o jsonpath='{.spec.clusterIP}') REDACTED" >> /shared/hosts
          echo "$(kubectl get svc k8s -n omni -o jsonpath='{.spec.clusterIP}') REDACTED" >> /shared/hosts
      volumeMounts:
        - name: hosts
          mountPath: /shared
    # Fixes the deploy key's ownership and a missing trailing newline OpenSSH needs —
    # see git-key-prep.sh.
    - name: git-key-prep
      image: "{{ $root.Values.automatron.image.repository }}:{{ $root.Values.automatron.image.tag }}"
      securityContext:
        runAsUser: 0
      command: ["/git-key-prep.sh"]
      volumeMounts:
        - name: git-ssh-key
          mountPath: /etc/git-secret
          readOnly: true
        - name: git-ssh-key-fixed
          mountPath: /fixed
    - name: git-clone
      image: registry.k8s.io/git-sync/git-sync:v4.2.4
      args:
        - --repo=git@github.com:HomeScaleCloud/homescale.git
        - --ref=main
        - --root=/repo
        - --link=current
        - --one-time
        - --ssh
        - --ssh-known-hosts=false
      env:
        - name: GITSYNC_SSH_KEY_FILE
          value: /etc/git-secret/sshPrivateKey
      volumeMounts:
        - name: repo
          mountPath: /repo
        - name: git-ssh-key-fixed
          mountPath: /etc/git-secret
          readOnly: true
  containers:
    - name: automatron
      image: "{{ $root.Values.automatron.image.repository }}:{{ $root.Values.automatron.image.tag }}"
      env:
        - name: PLAYBOOK
          value: {{ .playbook | quote }}
        - name: CLUSTER
          value: ""
        - name: DRY_RUN
          value: "false"
        - name: REPO_DIR
          value: /repo/current
        {{- with .chainNext }}
        - name: CHAIN_NEXT_CRONJOB
          value: {{ . | quote }}
        {{- end }}
      envFrom:
        - secretRef:
            name: automatron-secrets
        - secretRef:
            name: automatron-infisical-operator-creds
      volumeMounts:
        - name: repo
          mountPath: /repo
          readOnly: true
        - name: hosts
          mountPath: /etc/hosts
          subPath: hosts
{{- end -}}
