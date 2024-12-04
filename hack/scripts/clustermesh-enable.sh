#!/bin/bash

# For the first revision, we need to manually patch the clustermesh-clusters on the cilium-agent 
# This can be done by simply editing the cilium agent deployment in the cluster and changing the volume mounts as follows 

      # - name: clustermesh-secrets
      #   projected:
      #     defaultMode: 256
      #     sources:
      #     - secret:
      #         name: cilium-clustermesh
      #         optional: true
      #     - secret:
      #         items:
      #         - key: tls.key
      #           path: common-etcd-client.key
      #         - key: tls.crt
      #           path: common-etcd-client.crt
      #         - key: ca.crt
      #           path: common-etcd-client-ca.crt
      #         name: clustermesh-apiserver-remote-cert
      #         optional: true
      #     - secret:
      #         items:
      #         - key: tls.key
      #           path: local-etcd-client.key
      #         - key: tls.crt
      #           path: local-etcd-client.crt
      #         - key: ca.crt
      #           path: local-etcd-client-ca.crt
      #         name: clustermesh-apiserver-local-cert
      #         optional: true


# Variables
NAMESPACE="kube-system"
MANIFEST_OUTPUT_FILE="cilium-generated-manifests.yaml"
FILTERED_MANIFEST_FILE="cilium-filtered-manifests.yaml"

# Input Arguments
CLUSTER_ID=$1
CLUSTER_NAME=$2

# Check if required arguments are provided
if [[ -z "$CLUSTER_ID" || -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-id> <cluster-name>"
  exit 1
fi

kubectl config use-context $CLUSTER_NAME


# Step 1: Add Helm chart repo if not present (this does not install it, just makes it available for templating)
HELM_CHART_REPO="https://helm.cilium.io"
HELM_CHART_NAME="cilium/cilium"
if ! helm repo list | grep -q "$HELM_CHART_REPO"; then
  echo "Adding Cilium Helm repository..."
  helm repo add cilium "$HELM_CHART_REPO"
  helm repo update
fi

# Step 2: Generate all Kubernetes manifests using Helm template (dry-run)
echo "Generating all Kubernetes manifests with Helm template (dry-run)..."

# helm template cilium "$HELM_CHART_NAME" -n "$NAMESPACE" \
#   --set clustermesh.useAPIServer=true \
#   --set clustermesh.apiserver.tls.auto.enabled=true \
#   --set clustermesh.apiserver.tls.auto.method=cronJob \
#   --set clustermesh.apiserver.kvstoremesh.enabled=true \
#   --set clustermesh.config.enabled=false \
#   --set cluster.id="$CLUSTER_ID" \
#   --set cluster.name="$CLUSTER_NAME" \
#   --set externalWorkloads.enabled=true\
#   --dry-run > "$MANIFEST_OUTPUT_FILE"
kubectl patch configmap cilium-config -n kube-system --type=json -p '[
  {
    "op": "add",
    "path": "/data/cluster-id",
    "value": "'$CLUSTER_ID'"
  },
  {
    "op": "add",
    "path": "/data/cluster-name",
    "value": "'$CLUSTER_NAME'"
  }
]'

helm template cilium cilium/cilium -n kube-system \
  --set cluster.id="$CLUSTER_ID" \
  --set cluster.name=$CLUSTER_NAME \
  --set clustermesh.useAPIServer=true \
  --set externalWorkloads.enabled=false \
  --set clustermesh.apiserver.service.type="LoadBalancer" \
 --set-string clustermesh.apiserver.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-internal"="true" \
 --set clustermesh.apiserver.tls.auto.enabled=true \
  --set clustermesh.apiserver.kvstoremesh.enabled=true \
  --set clustermesh.config.enabled=true \
  --set hubble.enabled=false \
  --set envoy.enabled=false \
  --set clustermesh.apiserver.tls.auto.method="cronJob" \
  --dry-run > "$MANIFEST_OUTPUT_FILE"
# # helm template cilium "$HELM_CHART_NAME" -n "$NAMESPACE" \
# #   --set clustermesh.useAPIServer=true \
# #   --set externalWorkloads.enabled=false\
# #   --dry-run > "$MANIFEST_OUTPUT_FILE"
#   # --set clustermesh.apiserver.service.annotations.service.beta.kubernetes.io.azure-load-balancer-internal=true \

  

if [[ ! -s "$MANIFEST_OUTPUT_FILE" ]]; then
  echo "Error: Failed to generate Kubernetes manifests."
  exit 1
fi

# Step 4: Filter out cilium-config ConfigMap and cilium DaemonSet from the generated manifests
echo "Filtering out cilium-config ConfigMap and cilium DaemonSet..."

# Use `grep` to exclude cilium-config ConfigMap and cilium DaemonSet
yq eval 'select(
  ((.kind != "ConfigMap") or (.metadata.name != "cilium-config")) and
  ((.kind != "DaemonSet") or (.metadata.name != "cilium"))
)' "$MANIFEST_OUTPUT_FILE" > "$FILTERED_MANIFEST_FILE"


# if [[ ! -s "$FILTERED_MANIFEST_FILE" ]]; then
#   echo "Error: No resources left after filtering."
#   exit 1
# fi

# echo "Filtered manifests have been written to $FILTERED_MANIFEST_FILE."



# # Patch DaemonSet with volume mounts
echo "Patching cilium DaemonSet with volume mounts..."

kubectl patch daemonset cilium -n kube-system --type=strategic -p '{
  "spec": {
    "template": {
      "spec": {
        "volumes": [
          {
            "name": "clustermesh",
            "secret": {
              "secretName": "cilium-clustermesh",
              "optional": true
            }
          },
          {
            "name": "clustermesh-apiserver-remote-cert",
            "secret": {
              "secretName": "clustermesh-apiserver-remote-cert",
              "optional": true,
              "items": [
                {
                  "key": "tls.key",
                  "path": "common-etcd-client.key"
                },
                {
                  "key": "tls.crt",
                  "path": "common-etcd-client.crt"
                },
                {
                  "key": "ca.crt",
                  "path": "common-etcd-client-ca.crt"
                }
              ]
            }
          },
          {
            "name": "clustermesh-apiserver-local-cert",
            "secret": {
              "secretName": "clustermesh-apiserver-local-cert",
              "optional": true,
              "items": [
                {
                  "key": "tls.key",
                  "path": "local-etcd-client.key"
                },
                {
                  "key": "tls.crt",
                  "path": "local-etcd-client.crt"
                },
                {
                  "key": "ca.crt",
                  "path": "local-etcd-client-ca.crt"
                }
              ]
            }
          }
        ]
      }
    }
  }
}'


echo "Patches applied successfully!"
# # Step 5: Apply the filtered manifests using kubectl
# echo "Deploying the filtered components using kubectl..."
kubectl apply -f "$FILTERED_MANIFEST_FILE"

echo "Deployment completed. cilium-config ConfigMap and cilium DaemonSet excluded."
