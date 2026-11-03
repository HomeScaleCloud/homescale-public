apiVersion: v1alpha1
kind: KubeNetworkConfig
podSubnets:
  {{- toPrettyJson .Data.podSubnets | nindent 2 }}
serviceSubnets:
  {{- toPrettyJson .Data.serviceSubnets | nindent 2 }}
