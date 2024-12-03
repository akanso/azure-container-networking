#!/bin/bash
# usage ./clustermesh-connect.sh CLUSTER_1 CLUSTER2 (Order is important since the ids are derieved implicitly)

# Input arguments
CLUSTER1_CONTEXT=$1
CLUSTER2_CONTEXT=$2
SECRET_NAME="cilium-clustermesh"
NAMESPACE="kube-system"
CLUSTER_DOMAIN="svc.cluster.local"
SECRETS=("cilium-clustermesh" "cilium-kvstoremesh")

# Step 1: Create VNet Peering between the two clusters
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

# kubectl --context $CLUSTER2_CONTEXT delete secret -n kube-system cilium-kvstoremesh 
# kubectl --context=$CLUSTER1_CONTEXT get secret -n kube-system cilium-kvstoremesh -o yaml | \
#   kubectl --context $CLUSTER2_CONTEXT create -f -

# kubectl --context $CLUSTER2_CONTEXT delete secret -n kube-system clustermesh-apiserver-admin-cert 
# kubectl --context=$CLUSTER1_CONTEXT get secret -n kube-system clustermesh-apiserver-admin-cert  -o yaml | \
#   kubectl --context $CLUSTER2_CONTEXT create -f -

# kubectl --context $CLUSTER2_CONTEXT delete secret -n kube-system clustermesh-apiserver-remote-cert 
# kubectl --context=$CLUSTER1_CONTEXT get secret -n kube-system clustermesh-apiserver-remote-cert  -o yaml | \
#   kubectl --context $CLUSTER2_CONTEXT create -f -

# kubectl --context $CLUSTER2_CONTEXT delete secret -n kube-system clustermesh-apiserver-local-cert 
# kubectl --context=$CLUSTER1_CONTEXT get secret -n kube-system clustermesh-apiserver-local-cert  -o yaml | \
#   kubectl --context $CLUSTER2_CONTEXT create -f -

# kubectl --context $CLUSTER2_CONTEXT delete secret -n kube-system clustermesh-apiserver-server-cert
# kubectl --context=$CLUSTER1_CONTEXT get secret -n kube-system clustermesh-apiserver-server-cert -o yaml | \
#   kubectl --context $CLUSTER2_CONTEXT create -f -
# Function to get the clustermesh-apiserver IP
get_clustermesh_apiserver_ip() {
    local context=$1
    kubectl --context "$context" -n "$NAMESPACE" get svc clustermesh-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

# Step 2: Get the clustermesh-apiserver and node IPs for both clusters
CLUSTER1_APISERVER_IP=$(get_clustermesh_apiserver_ip "$CLUSTER1_CONTEXT")
CLUSTER2_APISERVER_IP=$(get_clustermesh_apiserver_ip "$CLUSTER2_CONTEXT")
CLUSTER1_NODE_IP=$(kubectl --context "$CLUSTER1_CONTEXT" get nodes -o wide --no-headers | awk '{print $6}')
CLUSTER2_NODE_IP=$(kubectl --context "$CLUSTER2_CONTEXT" get nodes -o wide --no-headers | awk '{print $6}')

echo "Cluster 1 Apiserver IP: $CLUSTER1_APISERVER_IP"
echo "Cluster 2 Apiserver IP: $CLUSTER2_APISERVER_IP"
echo "Cluster 1 Node IP: $CLUSTER1_NODE_IP"
echo "Cluster 2 Node IP: $CLUSTER2_NODE_IP"

MANIFEST_OUTPUT_FILE="cilium-generated-manifests.yaml"
FILTERED_MANIFEST_FILE="cilium-filtered-manifests.yaml"

# Function to patch secrets and configure the clustermesh
patch_secret() {
    local remote_ip=$1
    local remote_name=$2
    local local_id=$3
    local local_name=$4
    local ca_cert=$5
    local cert=$6
    local key=$7
 #   tls:
    #     cert: ""
    #     key: ""
    #     caCert: ""
    helm template cilium cilium/cilium \
        --set cluster.id="$local_id" \
        --set cluster.name="$local_name" \
        --set clustermesh.useAPIServer=true \
  --set clustermesh.apiserver.tls.auto.enabled=true \
  --set clustermesh.apiserver.kvstoremesh.enabled=true \
  --set clustermesh.config.enabled=true \
        --set clustermesh.apiserver.kvstoremesh.enabled=true \
        --set clustermesh.apiserver.service.type=NodePort \
        --set clustermesh.config.clusters[0].ips[0]="$remote_ip" \
        --set clustermesh.config.clusters[0].name="$remote_name" \
        --set clustermesh.config.clusters[0].port=32379 \
        --set clustermesh.config.clusters[0].tls.caCert="$ca_cert" \
        --set clustermesh.config.clusters[0].tls.cert="$cert" \
        --set clustermesh.config.clusters[0].tls.key="$key" \
        --set clustermesh.config.enabled=true \
        --set hubble.enabled=false \
        --set clustermesh.useAPIServer=true \
  --set externalWorkloads.enabled=false \
  --set envoy.enabled=false \
        --dry-run > "$MANIFEST_OUTPUT_FILE"

    echo "Filtering out cilium-config ConfigMap and cilium DaemonSet..."

    # Filter out specific resources from the manifest
   yq eval 'select(
  ((.kind != "ConfigMap") or (.metadata.name != "cilium-config")) and
  ((.kind != "DaemonSet") or (.metadata.name != "cilium"))
)' "$MANIFEST_OUTPUT_FILE" > "$FILTERED_MANIFEST_FILE"

    kubectl apply -f "$FILTERED_MANIFEST_FILE"
    kubectl rollout restart deployment clustermesh-apiserver
}

CLUSTER1_CA=$(kubectl get secret cilium-ca -o jsonpath='{.data.ca\.crt}' --context $CLUSTER1_CONTEXT) 
CLUSTER1_CERT=$(kubectl get secret  clustermesh-apiserver-remote-cert  -o jsonpath='{.data.tls\.crt}' --context $CLUSTER1_CONTEXT) 
CLUSTER1_KEY=$(kubectl get secret  clustermesh-apiserver-remote-cert  -o jsonpath='{.data.tls\.key}'  --context $CLUSTER1_CONTEXT)

CLUSTER2_CA=$(kubectl get secret cilium-ca -o jsonpath='{.data.ca\.crt}' --context $CLUSTER2_CONTEXT) 
CLUSTER2_CERT=$(kubectl get secret  clustermesh-apiserver-remote-cert  -o jsonpath='{.data.tls\.crt}' --context $CLUSTER2_CONTEXT) 
CLUSTER2_KEY=$(kubectl get secret  clustermesh-apiserver-remote-cert  -o jsonpath='{.data.tls\.key}' --context $CLUSTER2_CONTEXT) 

# Step 3: Configure secrets for both clusters
kubectl config use-context "$CLUSTER1_CONTEXT"
echo "patch_secret $CLUSTER2_NODE_IP $CLUSTER2_CONTEXT 1 $CLUSTER1_CONTEXT $CLUSTER2_CA $CLUSTER2_CERT $CLUSTER2_KEY"

patch_secret "$CLUSTER2_NODE_IP" "$CLUSTER2_CONTEXT" 1 "$CLUSTER1_CONTEXT" "$CLUSTER2_CA" "$CLUSTER2_CERT" "$CLUSTER2_KEY"
kubectl config use-context "$CLUSTER2_CONTEXT"
echo "patch_secret $CLUSTER2_NODE_IP $CLUSTER2_CONTEXT 1 $CLUSTER2_CONTEXT $CLUSTER1_CA $CLUSTER1_CERT $CLUSTER1_KEY"
patch_secret "$CLUSTER1_NODE_IP" "$CLUSTER1_CONTEXT" 2 "$CLUSTER2_CONTEXT" $CLUSTER1_CA $CLUSTER1_CERT $CLUSTER1_KEY


echo "Secrets and hostAliases have been successfully configured in both clusters!"
