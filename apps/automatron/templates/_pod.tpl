{{/*
Shared jobTemplate.spec.template for automatron's CronJobs. Call with:
  include "automatron.podTemplate" (dict "root" $ "playbook" "bootstrap-cluster" "chainNext" "automatron-bootstrap-cluster")
"playbook" is the default PLAYBOOK env value; "chainNext" (optional) sets
CHAIN_NEXT_CRONJOB so this run triggers that CronJob's jobTemplate on success.
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
    # Omni lives in this same cluster (mgmt) — its `api`/`k8s` Services (apps/omni/
    # templates/service.yaml) already have ClusterIPs regardless of their Tailscale
    # LoadBalancer status, so automatron reaches Omni entirely in-cluster rather than
    # over Tailscale, keeping the client-facing hostnames (and therefore TLS cert
    # validation against the real REDACTED cert — a real Let's
    # Encrypt cert, so it can't cover .svc.cluster.local names instead) unchanged —
    # only where they resolve to changes. Helm's `lookup` (resolved at render time)
    # isn't reliable here — ArgoCD's own renders have been observed returning empty
    # for it — so this resolves the real ClusterIPs at pod start instead, via a
    # scoped Role/RoleBinding (templates/role.yaml, templates/rolebinding.yaml) letting automatron's own
    # ServiceAccount `get` just these two Services in the omni namespace, and writes
    # a corrected /etc/hosts to a shared volume — the automatron container mounts it
    # over its own (non-root, and /etc/hosts isn't group/other-writable, so it can't
    # patch this itself).
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
    # Fixes the deploy key's ownership (k8s secret files are always root-owned; git-sync's
    # non-root UID can't read them, and widening via fsGroup won't work either since
    # sshd rejects any group/other bits) and a missing trailing newline the stored value
    # needs OpenSSH's parser to accept — see git-key-prep.sh for the full why. Runs as
    # root (only this container needs to) on automatron's own image, not git-sync's, so
    # this logic is a real versioned script rather than inline shell here.
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
