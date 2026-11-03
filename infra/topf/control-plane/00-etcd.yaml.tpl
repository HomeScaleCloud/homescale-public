cluster:
  etcd:
    advertisedSubnets:
      - {{ .Data.nodeSubnet }}
