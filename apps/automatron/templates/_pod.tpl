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
    - name: tailscale-state
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
    # Secret-mounted files are root-owned with mode 0600 (required — sshd's strict
    # key-perm check rejects any group/other bits), so git-sync's own non-root UID
    # can't read it directly. Separately, the key's stored value (an Infisical
    # secret reference to the same value ArgoCD's deploy key uses) is missing the
    # trailing newline after "-----END OPENSSH PRIVATE KEY-----" that OpenSSH's
    # new-format key parser needs — without it, ssh fails with a generic "error in
    # libcrypto" trying to load it (confirmed directly: identical content with the
    # newline restored authenticates fine, without it it doesn't, regardless of
    # which user reads it). This prep step (root, to read the secret at all) fixes
    # both: copies the key into a writable volume, restores the trailing newline if
    # missing, and hands ownership to git-sync's actual non-root UID so git-clone
    # can run as its normal user rather than needing root itself.
    - name: git-key-prep
      image: registry.k8s.io/git-sync/git-sync:v4.2.4
      securityContext:
        runAsUser: 0
      command: ["sh", "-c"]
      args:
        - |
          set -e
          cp /etc/git-secret/sshPrivateKey /fixed/sshPrivateKey
          if [ -n "$(tail -c1 /fixed/sshPrivateKey)" ]; then
            printf '\n' >> /fixed/sshPrivateKey
          fi
          chown 65533:65533 /fixed/sshPrivateKey
          chmod 600 /fixed/sshPrivateKey
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
    - name: tailscale
      image: tailscale/tailscale:v1.102.2
      restartPolicy: Always
      env:
        - name: TS_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: automatron-secrets # pragma: allowlist secret
              key: TAILSCALE_CLIENT_ID
        - name: TS_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: automatron-secrets # pragma: allowlist secret
              key: TAILSCALE_CLIENT_SECRET
        - name: TS_USERSPACE
          value: "false"
        - name: TS_KUBE_SECRET
          value: ""
        - name: TS_STATE_DIR
          value: /var/lib/tailscale
        - name: TS_HOSTNAME
          value: "automatron-{{ $root.Values.cluster.name }}"
        - name: TS_EXTRA_ARGS
          value: "--advertise-tags=tag:k8s,tag:app-automatron"
        - name: TS_ACCEPT_DNS
          value: "false"
        - name: TS_AUTH_ONCE
          value: "true"
        - name: TS_ENABLE_HEALTH_CHECK
          value: "true"
      startupProbe:
        httpGet:
          path: /healthz
          port: 9002
        periodSeconds: 3
        failureThreshold: 40
      securityContext:
        capabilities:
          add:
            - NET_ADMIN
      volumeMounts:
        - name: tailscale-state
          mountPath: /var/lib/tailscale
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
        - secretRef:
            name: automatron-omni-creds
      volumeMounts:
        - name: repo
          mountPath: /repo
          readOnly: true
{{- end -}}
