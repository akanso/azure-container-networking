#!/bin/bash

# Input arguments
CLUSTER1_CONTEXT=$1
CLUSTER2_CONTEXT=$2
SECRET_NAME="cilium-clustermesh"
NAMESPACE="kube-system"
CLUSTER_DOMAIN="svc.cluster.local"
SECRETS=("cilium-clustermesh" "cilium-kvstoremesh")

az network vnet peering create \
    -g "$CLUSTER1_CONTEXT" \
    --name "peering-$CLUSTER1_CONTEXT-to-$CLUSTER2_CONTEXT" \
    --vnet-name "$CLUSTER1_CONTEXT" \
    --remote-vnet "/subscriptions/d9eabe18-12f6-4421-934a-d7e2327585f5/resourceGroups/$CLUSTER2_CONTEXT/providers/Microsoft.Network/virtualNetworks/$CLUSTER2_CONTEXT" \
    --allow-vnet-access

az network vnet peering create \
    -g "$CLUSTER2_CONTEXT" \
    --name "peering-$CLUSTER2_CONTEXT-to-$CLUSTER1_CONTEXT" \
    --vnet-name "$CLUSTER2_CONTEXT" \
    --remote-vnet "/subscriptions/d9eabe18-12f6-4421-934a-d7e2327585f5/resourceGroups/$CLUSTER1_CONTEXT/providers/Microsoft.Network/virtualNetworks/$CLUSTER1_CONTEXT" \
    --allow-vnet-access
kubectl --context $CLUSTER2_CONTEXT delete secret -n kube-system cilium-ca
kubectl --context=$CLUSTER1_CONTEXT get secret -n kube-system cilium-ca -o yaml | \
  kubectl --context $CLUSTER2_CONTEXT create -f -
# # Function to get service IP for the clustermesh-apiserver service in the kube-system namespace
# get_service_ip() {
#     local context=$1
#     kubectl --context="$context" get svc clustermesh-apiserver -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# }

# # Step 1: Copy secrets from source context to destination context


# # Step 2: Extract Service IPs from the destination context
# SERVICE_IP=$(get_service_ip "$CLUSTER2_CONTEXT")

# if [[ -z "$SERVICE_IP" ]]; then
#     echo "ERROR: Unable to fetch Service IP for clustermesh-apiserver from $CLUSTER2_CONTEXT"
#     exit 1
# fi

# echo "Extracted Service IP for clustermesh-apiserver: $SERVICE_IP"

# # Step 3: Update the Helm command with the service IP and TLS info
# HELM_COMMAND="helm upgrade cilium cilium/cilium -n kube-system\
# --set clustermesh.config.clusters[0].ips[0]="$SERVICE_IP"\
# --set clustermesh.config.clusters[0].name="test-cmesh-2"\
#             --set clustermesh.config.clusters[0].port=2379  >>


# # Exit on error
# set -e

# # Check for required arguments
# if [ "$#" -ne 2 ]; then
#   echo "Usage: $0 <context1> <context2>"
#   exit 1
# fi

# # Input arguments


# Function to get the clustermesh-apiserver IP
get_clustermesh_apiserver_ip() {
  local context=$1
  kubectl --context "$context" -n "$NAMESPACE" get svc clustermesh-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

# Function to create or patch a secret
patch_secret() {
  local context=$1
  local secret_name=$2
  local cluster_name=$3
  local remote_creds=$4

  echo "Patching secret '$secret_name' in context '$context' for cluster '$cluster_name'"

  kubectl --context "$context" -n "$NAMESPACE" get secret "$secret_name" &>/dev/null && {
    # If secret exists, patch it
    kubectl --context "$context" -n "$NAMESPACE" patch secret "$secret_name" --type=merge -p="
    {
      \"data\": {
        \"${cluster_name}\": \"${remote_creds}\"
      }
    }"
  } || {
    # If secret does not exist, create it
    kubectl --context "$context" -n "$NAMESPACE" create secret generic "$secret_name" \
      -n "$NAMESPACE" --from-literal="${cluster_name}=${remote_creds}"
  }
}




# Step 1: Get the clustermesh-apiserver IPs
CLUSTER1_APISERVER_IP=$(get_clustermesh_apiserver_ip "$CLUSTER1_CONTEXT")
CLUSTER2_APISERVER_IP=$(get_clustermesh_apiserver_ip "$CLUSTER2_CONTEXT")
CLUSTER1_NODE_IP=$(kubectl --context $CLUSTER1_CONTEXT get nodes -o wide --no-headers | awk '{print $6}')
CLUSTER2_NODE_IP=$(kubectl --context $CLUSTER1_CONTEXT get nodes -o wide --no-headers | awk '{print $6}')

echo "Cluster 1 Apiserver IP: $CLUSTER1_APISERVER_IP"
echo "Cluster 2 Apiserver IP: $CLUSTER2_APISERVER_IP"

MANIFEST_OUTPUT_FILE="cilium-generated-manifests.yaml"
FILTERED_MANIFEST_FILE="cilium-filtered-manifests.yaml" 

patch_secret() {
  local remote_ip=$1
  local remote_name=$2
  local local_id=$3
  local local_name=$4
  helm template cilium cilium/cilium -n kube-system \
  --set cluster.id=$local_id\
  --set cluster.name=$local_name \
  --set clustermesh.useAPIServer=true \
  --set externalWorkloads.enabled=false \
  --set clustermesh.apiserver.service.type="NodePort" \
  --set clustermesh.apiserver.tls.auto.enabled=false \
  --set clustermesh.apiserver.authentication.enabled=false \
  --set clustermesh.apiserver.kvstoremesh.enabled=true \
  --set clustermesh.config.enabled=false \
  --set clustermesh.apiserver.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-internal"="\"true\"" \
  --set envoy.enabled=false \
  --set clustermesh.config.clusters[0].ips[0]="$remote_ip"\
  --set clustermesh.config.clusters[0].name="$remote_name"\
  --set clustermesh.config.clusters[0].port=2379  --dry-run > "$MANIFEST_OUTPUT_FILE"

  echo "Filtering out cilium-config ConfigMap and cilium DaemonSet..."

# Use `grep` to exclude cilium-config ConfigMap and cilium DaemonSet
yq eval 'select(
  ((.kind != "ConfigMap") or (.metadata.name != "cilium-config")) and
  ((.kind != "DaemonSet") or (.metadata.name != "cilium"))
)' "$MANIFEST_OUTPUT_FILE" > "$FILTERED_MANIFEST_FILE"


kubectl apply -f "$FILTERED_MANIFEST_FILE"

}

kubectl config use-context $CLUSTER1_CONTEXT
patch_secret $CLUSTER1_NODE_IP $CLUSTER2_CONTEXT 1 $CLUSTER1_CONTEXT

kubectl config use-context $CLUSTER2_CONTEXT
patch_secret $CLUSTER2_NODE_IP $CLUSTER1_CONTEXT 2 $CLUSTER2_CONTEXT

echo "Secrets and hostAliases have been successfully configured in both clusters!"

# kubectl --context $CLUSTER2_CONTEXT delete secret -n kube-system cilium-ca
# kubectl --context=$CLUSTER1_CONTEXT get secret -n kube-system cilium-ca -o yaml | \
#   kubectl --context $CLUSTER2_CONTEXT create -f -