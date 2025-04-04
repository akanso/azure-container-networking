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
    # make -C ./hack/aks $clusterType \
    #     AZCLI=az REGION=westus2 SUB=$SUB \
    #     CLUSTER=${clusterPrefix}-${unique} \
    #     POD_CIDR=192.${unique}0.0.0/16 SVC_CIDR=192.${unique}1.0.0/16 DNS_IP=192.${unique}1.0.10 \
    #     VNET_PREFIX=10.${unique}0.0.0/16 SUBNET_PREFIX=10.${unique}0.0.0/16
    kubectl config use-context ${clusterPrefix}-${unique}
    cluster_id=1
    if (( unique % 2 == 0 )); then
        echo "overriding cluster id to 2 for $unique"
        cluster_id=2
    fi
    if [ $install == "helm" ]; then
        helm upgrade --install -n kube-system cilium cilium/cilium --version v1.16.1 \
        --set azure.resourceGroup=${clusterPrefix}-${unique}-rg --set cluster.id=${cluster_id} \
        --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
        --set cluster.name=${clusterPrefix}-${unique} \
        --set hubble.enabled=false \
        --set ipam.mode=delegated-plugin \
        --set debug.enabled=true \
        --set image.repository=acnpublic.azurecr.io/cilium/cilium \
        --set image.tag=krunaljainhybridtest \
        --set image.useDigest=false \
        --set debug.verbose="datapath" \
        --set endpointRoutes.enabled=true \
        --set bpf.hostLegacyRouting=true \
        --set aksbyocni.enabled=false \
        --set nodeinit.enabled=false \
        --set envoy.enabled=false \
        --set enable-ipv4=true \
        --set kubeProxyReplacement=true \
        --set kubeProxyReplacementHealthzBindAddr='0.0.0.0:10256' \
        --set extraArgs="{--local-router-ipv4=192.${unique}0.0.7} {--install-iptables-rules=true}" \
        --set endpointHealthChecking.enabled=false \
        --set cni.exclusive=false \
        --set bpf.enableTCX=false \
        --set bpf.hostLegacyRouting=true \
        --set l7Proxy=false \
        --set sessionAffinity=true

        make test-load CNS_ONLY=true \
        AZURE_IPAM_VERSION=v0.2.0 CNS_VERSION=v1.5.32 \
        INSTALL_CNS=true INSTALL_OVERLAY=true \
        CNS_IMAGE_REPO=MCR IPAM_IMAGE_REPO=MCR
        kubectl get pods --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNETWORK:.spec.hostNetwork --no-headers=true | grep '<none>' | awk '{print "-n "$1" "$2}' | xargs -L 1 -r kubectl delete pod
    fi
done

cd hack/scripts

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
