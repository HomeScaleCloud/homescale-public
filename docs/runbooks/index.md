# Runbooks

Runbooks for alerts fired by Prometheus. Each alert links back to this page via its `runbook_url` annotation.

## Omni

| Alert | Severity |
|-------|----------|
| [OmniDown](omni-down.md) | critical |
| [OmniNoConnectedMachines](omni-no-connected-machines.md) | critical |
| [OmniNoMachines](omni-no-machines.md) | critical |
| [OmniSecureBootDisabled](omni-secure-boot-disabled.md) | warning |

## ArgoCD

| Alert | Severity |
|-------|----------|
| [ArgoAppStuck](argo-app-stuck.md) | warning |

## PDU

| Alert | Severity |
|-------|----------|
| [ApcPduOffline](apc-pdu-offline.md) | critical |
| [ApcPduVoltageCritical](apc-pdu-voltage-critical.md) | critical |
| [ApcPduBankNearOverload](apc-pdu-bank-near-overload.md) | critical |
| [ApcPduBankLoadHigh](apc-pdu-bank-load-high.md) | critical |
| [ApcPduVoltageWarning](apc-pdu-voltage-warning.md) | warning |

## VolSync

| Alert | Severity |
|-------|----------|
| [VolSyncMissedBackupInterval](volsync-missed-backup-interval.md) | critical |
| [VolSyncMoverJobFailed](volsync-mover-job-failed.md) | critical |
| [VolSyncControllerDown](volsync-controller-down.md) | critical |

## NetBird

| Alert | Severity |
|-------|----------|
| [NetBirdOperatorDown](netbird-operator-down.md) | critical |
| [NetBirdClusterProxyNotReady](netbird-clusterproxy-not-ready.md) | critical |
| [NetBirdNetworkRouterNotReady](netbird-networkrouter-not-ready.md) | critical |
| [NetBirdNetworkResourceNotReady](netbird-networkresource-not-ready.md) | warning |
| [NetBirdReconcileErrors](netbird-reconcile-errors.md) | warning |
| [NetBirdWorkqueueBacklog](netbird-workqueue-backlog.md) | warning |

## Longhorn

| Alert | Severity |
|-------|----------|
| [LonghornVolumeFaulted](longhorn-volume-faulted.md) | critical |
| [LonghornVolumeDegraded](longhorn-volume-degraded.md) | warning |
| [LonghornVolumeSpaceFilling](longhorn-volume-space-filling.md) | warning |
| [LonghornDiskFailed](longhorn-disk-failed.md) | critical |
| [LonghornDiskNotReady](longhorn-disk-not-ready.md) | critical |
| [LonghornDiskStorageWarning](longhorn-disk-storage-warning.md) | warning |
| [LonghornDiskStorageCritical](longhorn-disk-storage-critical.md) | critical |
| [LonghornNodeDown](longhorn-node-down.md) | critical |
| [LonghornNodeNotReady](longhorn-node-not-ready.md) | critical |
| [LonghornNodeStorageWarning](longhorn-node-storage-warning.md) | warning |
