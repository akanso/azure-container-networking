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
cd ../..
for unique in $sufixes; do
    if (( unique % 2 == 0 )); then
        cluster_id=2  # Even unique, set cluster_id to 2
    else
        cluster_id=1 
    fi 
    make -C ./hack/aks $clusterType \
        AZCLI=az REGION=westus2 SUB=$SUB \
        CLUSTER=${clusterPrefix}-${unique} \
        POD_CIDR=192.${unique}0.0.0/16 SVC_CIDR=192.${unique}1.0.0/16 DNS_IP=192.${unique}1.0.10 \
        VNET_PREFIX=10.${unique}0.0.0/16 SUBNET_PREFIX=10.${unique}0.0.0/16
    kubectl config use-context ${clusterPrefix}-${unique}
    helm upgrade --install -n kube-system cilium cilium/cilium --version v1.16.1 \
                --set azure.resourceGroup=${clusterPrefix}-${unique}-rg \
                --set cluster.id=$cluster_id \
                --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
                --set cluster.name=${clusterPrefix}-${unique} \
                --set debug.enabled=true \
                --set debug.verbose="datapath" \
                --set endpointRoutes.enabled=true \
                --set bpf.hostLegacyRouting=true \
                --set envoy.enabled=false
    # cd ../cilium
    # ./deploy_image.sh krunaljainhybridtest ${clusterPrefix}-${unique}
    # cd ../azure-container-networking
done

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


cilium clustermesh enable --context ${clusterPrefix}-${sufix1} --service-type NodePort --enable-kvstoremesh=true
cilium clustermesh enable --context ${clusterPrefix}-${sufix2} --service-type NodePort --enable-kvstoremesh=true

# # CA is passed between clusters in this step
cilium clustermesh connect --context ${clusterPrefix}-${sufix1} --destination-context ${clusterPrefix}-${sufix2}
# These can be run in parallel in different bash shells
