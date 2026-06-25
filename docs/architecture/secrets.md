# Secrets

Infisical is the secrets store. The Infisical k8s operator (syncWave -35) syncs secrets from Infisical into cluster namespaces via `InfisicalSecret` CRs.

**No secrets belong in this repo.** The `detect-secrets` pre-commit hook catches accidental commits. Use `# pragma: allowlist secret` to suppress false positives on non-secret strings (e.g. secret names).

## Secret path convention

```
/k8s/<purpose>/<cluster-name>/<app>
```

For example, VolSync restic credentials live at `/k8s/volsync/<cluster-name>/<app>` and are synced into a secret named `<app>-volsync-repo` in the app's namespace.
