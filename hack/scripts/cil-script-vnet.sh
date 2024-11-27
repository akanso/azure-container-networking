#!/bin/bash
# Requires
# sufix1 - unique single digit whole number 1-9. Cannot match sufix2
# sufix2 - unique single digit whole number 1-9. Cannot match sufix1
# SUB - GUID for subscription
# clusterType - overlay-byocni-nokubeproxy-up-mesh is primary atm, but leaving for testing later.
# Example command: clusterPrefix=<alais> sufix1=1 sufix2=2 SUB=<GUID> clusterType=overlay-byocni-nokubeproxy-up-mesh ./cil-script-vnet.sh
sufix1=1
sufix2=2
sufixes="${sufix1} ${sufix2}"
install="acn"
echo "sufixes ${sufixes}"

cd ../..
make -C ./hack/aks overlay-byocni-nokubeproxy-up-mesh-singlevnet \
    AZCLI=az REGION=westus2 SUB=$SUB \
    CLUSTER=${clusterPrefix} \
    VNET_PREFIX=10.0.0.0/8
for unique in $sufixes; do
    az aks get-credentials -n ${clusterPrefix}${unique} -g ${clusterPrefix}-rg
    if [ $install == "helm" ]; then
        cilium install -n kube-system cilium cilium/cilium --version v1.16.1 \
        --set azure.resourceGroup=${clusterPrefix}-rg --set cluster.id=${unique} \
        --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
        --set hubble.enabled=false \
        --set envoy.enabled=false

    else # Ignore this block for now, was testing internal resources.
        export CILIUM_VERSION_TAG=v1.14.15-241024
        export CILIUM_IMAGE_REGISTRY=mcr.microsoft.com/containernetworking
        export DIR=1.14
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-config/cilium-config.yaml
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-agent/files
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-operator/files
        envsubst '${CILIUM_VERSION_TAG},${CILIUM_IMAGE_REGISTRY}' < test/integration/manifests/cilium/v${DIR}/cilium-agent/templates/daemonset.yaml | kubectl apply -f -
        envsubst '${CILIUM_VERSION_TAG},${CILIUM_IMAGE_REGISTRY}' < test/integration/manifests/cilium/v${DIR}/cilium-operator/templates/deployment.yaml | kubectl apply -f -
    fi

    make test-load CNS_ONLY=true \
        AZURE_IPAM_VERSION=v0.2.0 CNS_VERSION=v1.5.32 \
        INSTALL_CNS=true INSTALL_OVERLAY=true \
        CNS_IMAGE_REPO=MCR IPAM_IMAGE_REPO=MCR
done

cd hack/scripts

# VNET_ID1=$(az network vnet show \
#     --resource-group "${clusterPrefix}-${sufix1}-rg" \
#     --name "${clusterPrefix}-${sufix1}-vnet" \
#     --query id -o tsv)

# VNET_ID2=$(az network vnet show \
#     --resource-group "${clusterPrefix}-${sufix2}-rg" \
#     --name "${clusterPrefix}-${sufix2}-vnet" \
#     --query id -o tsv)

# az network vnet peering create \
#     -g "${clusterPrefix}-${sufix1}-rg" \
#     --name "peering-${clusterPrefix}-${sufix1}-to-${clusterPrefix}-${sufix2}" \
#     --vnet-name "${clusterPrefix}-${sufix1}-vnet" \
#     --remote-vnet "${VNET_ID2}" \
#     --allow-vnet-access

# az network vnet peering create \
#     -g "${clusterPrefix}-${sufix2}-rg" \
#     --name "peering-${clusterPrefix}-${sufix2}-to-${clusterPrefix}-${sufix1}" \
#     --vnet-name "${clusterPrefix}-${sufix2}-vnet" \
#     --remote-vnet "${VNET_ID1}" \
#     --allow-vnet-access


# cilium clustermesh enable --context ${clusterPrefix}${sufix1} --enable-kvstoremesh=true
# cilium clustermesh enable --context ${clusterPrefix}${sufix2} --enable-kvstoremesh=true


# cilium clustermesh status --context ${clusterPrefix}${sufix1} --wait
# cilium clustermesh status --context ${clusterPrefix}${sufix2} --wait

# # CA is passed between clusters in this step
# cilium clustermesh connect --context ${clusterPrefix}${sufix1} --destination-context ${clusterPrefix}${sufix2}

