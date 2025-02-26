#!/bin/bash
# Requires
# sufix1 - unique single digit whole number 1-9. Cannot match sufix2
# sufix2 - unique single digit whole number 1-9. Cannot match sufix1
# SUB - GUID for subscription
# clusterType - overlay-byocni-nokubeproxy-up-mesh is primary atm, but leaving for testing later.
# Example command: clusterPrefix=<alais> sufix1=1 sufix2=2 SUB=<GUID> clusterType=overlay-byocni-nokubeproxy-up-mesh ./cil-script.sh

sufixes="${sufix1} ${sufix2}"
install=helm
echo "sufixes ${sufixes}"

TAG=krunaljainhybridtest
REGISTRY="acnpublic.azurecr.io"
CILIUM_IMAGE="$REGISTRY/cilium/cilium:$TAG"
# Step 1: Login to Azure Container Registry
echo "Logging in to Azure Container Registry..."
az acr login -n acnpublic
if [[ $? -ne 0 ]]; then
  echo "Failed to log in to Azure Container Registry. Exiting."
  exit 1
fi

# Step 2: Build the Cilium Docker image
echo "Building the Cilium Docker image..."
unset ARCH
DOCKER_FLAGS="--platform linux/amd64"
make docker-cilium-image

# Step 3: Tag and push the Cilium Docker image
echo "Tagging and pushing the Cilium Docker image..."
docker tag quay.io/cilium/cilium:latest "$CILIUM_IMAGE"
docker push "$CILIUM_IMAGE"
if [[ $? -ne 0 ]]; then
  echo "Failed to push the Cilium Docker image. Exiting."
  exit 1
fi



# Step 6: Retrieve the image digest for the newly pushed Cilium image
CILIUM_IMAGE_SHA=$(az acr repository show-manifests --name acnpublic --repository cilium/cilium --query "[?tags[?contains(@, '$TAG')]].digest" -o tsv)
if [[ -z "$CILIUM_IMAGE_SHA" ]]; then
  echo "Failed to retrieve the Cilium image digest. Exiting."
  exit 1
fi

cd ../..
for unique in $sufixes; do
    # make -C ./hack/aks $clusterType \
    #     AZCLI=az REGION=westus2 SUB=$SUB \
    #     CLUSTER=${clusterPrefix}-${unique} \
    #     POD_CIDR=192.${unique}0.0.0/16 SVC_CIDR=192.${unique}1.0.0/16 DNS_IP=192.${unique}1.0.10 \
    #     VNET_PREFIX=10.${unique}0.0.0/16 SUBNET_PREFIX=10.${unique}0.0.0/16
        echo "Cluster Prefix: ${clusterPrefix}"
        echo "Unique ID: ${unique}"
        echo "Resource Group: ${clusterPrefix}-${unique}-rg"
        echo "Cluster Name: ${clusterPrefix}-${unique}"
        cilium upgrade install -n kube-system cilium cilium/cilium --version v1.16.1 \
                --set image.repository=$REGISTRY/cilium/cilium \
                --set image.tag=$TAG \
                --set image.digest=$CILIUM_IMAGE_SHA \
                --set azure.resourceGroup=${clusterPrefix}-${unique}-rg \
                --set aksbyocni.enabled=false \
                --set nodeinit.enabled=false \
                --set hubble.enabled=false \
                --set envoy.enabled=false \
                --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
                --set cluster.id=${unique} \
                --set cluster.name=${clusterPrefix}-${unique} \
                --set ipam.mode=delegated-plugin \
                --set endpointRoutes.enabled=true \
                --set enable-ipv4=true \
                --set enableIPv4Masquerade=false \
                --set kubeProxyReplacement=true \
                --set kubeProxyReplacementHealthzBindAddr='0.0.0.0:10256' \
                --set extraArgs="{--local-router-ipv4=169.254.23.0} {--install-iptables-rules=true}" \
                --set endpointHealthChecking.enabled=false \
                --set cni.exclusive=false \
                --set bpf.enableTCX=false \
                --set bpf.hostLegacyRouting=true \
                --set l7Proxy=false \
                --set sessionAffinity=true
done

cd ../cilium 
./deploy_image.sh krunaljaincustom "${clusterPrefix}-${sufix1}"
./deploy_image.sh krunaljaincustom "${clusterPrefix}-${sufix2}"
cd ../azure-container-networking/hack/scripts

VNET_ID1=$(az network vnet show \
    --resource-group "${clusterPrefix}-${sufix1}-rg" \
    --name "${clusterPrefix}-${sufix1}-vnet" \
    --query id -o tsv)

VNET_ID2=$(az network vnet show \
    --resource-group "${clusterPrefix}-${sufix2}-rg" \
    --name "${clusterPrefix}-${sufix2}-vnet" \
    --query id -o tsv)

az network vnet peering create \
    -g "${clusterPrefix}-${sufix1}-rg" \
    --name "peering-${clusterPrefix}-${sufix1}-to-${clusterPrefix}-${sufix2}" \
    --vnet-name "${clusterPrefix}-${sufix1}-vnet" \
    --remote-vnet "${VNET_ID2}" \
    --allow-vnet-access

az network vnet peering create \
    -g "${clusterPrefix}-${sufix2}-rg" \
    --name "peering-${clusterPrefix}-${sufix2}-to-${clusterPrefix}-${sufix1}" \
    --vnet-name "${clusterPrefix}-${sufix2}-vnet" \
    --remote-vnet "${VNET_ID1}" \
    --allow-vnet-access


cilium clustermesh enable --context ${clusterPrefix}-${sufix1} --enable-kvstoremesh=true
cilium clustermesh enable --context ${clusterPrefix}-${sufix2} --enable-kvstoremesh=true


cilium clustermesh status --context ${clusterPrefix}-${sufix1} --wait
cilium clustermesh status --context ${clusterPrefix}-${sufix2} --wait

# # CA is passed between clusters in this step
cilium clustermesh connect --context ${clusterPrefix}-${sufix1} --destination-context ${clusterPrefix}-${sufix2}
# These can be run in parallel in different bash shells
