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
    make -C ./hack/aks overlay-byocni-nokubeproxy-up-mesh \
        AZCLI=az REGION=westus2 SUB=$SUB \
        CLUSTER=${clusterPrefix}-${unique} \
        POD_CIDR=192.${unique}0.0.0/16 SVC_CIDR=192.${unique}1.0.0/16 DNS_IP=192.${unique}1.0.10 \
        VNET_PREFIX=10.${unique}${unique}.0.0/16 SUBNET_PREFIX=10.${unique}${unique}.10.0/24
    cat << EOF | kubectl apply -f -
    apiVersion: v1
    kind: ConfigMap
    metadata:
        name: cni-configuration
        namespace: kube-system
    data:
        cni-config: |-
            {
                "cniVersion": "0.3.1",
                "name": "cilium",
                "plugins": [
                    {
                        "type": "cilium-cni",
                        "ipam": {
                            "type": "azure-ipam"
                        },
                        "enable-debug": true,
                        "log-file": "/var/log/cilium-cni.log"
                    }
                ]
            }
EOF
    if [ $install == "helm" ]; then
        helm upgrade --install -n kube-system cilium cilium/cilium  \
            --set azure.resourceGroup=${clusterPrefix}-${unique}-rg \
            --set aksbyocni.enabled=false \
            --set nodeinit.enabled=false \
            --set hubble.enabled=false \
            --set envoy.enabled=false \
            --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
            --set cluster.id=${unique} \
            --set cluster.name=${clusterPrefix}-${unique} \
            --set endpointRoutes.enabled=true \
            --set debug.enabled=true \
            --set ipam.mode="delegated-plugin" \
            --set debug.verbose="datapath" \
            --set enable-ipv4=true \
            --set kubeProxyReplacement=true \
            --set kubeProxyReplacementHealthzBindAddr='0.0.0.0:10256' \
            --set extraArgs="{--local-router-ipv4=192.${unique}0.0.9} {--install-iptables-rules=true}" \
            --set endpointHealthChecking.enabled=false \
            --set cni.exclusive=false \
            --set cni.install=true \
            --set cni.customConf=true \
            --set cni.configMap="cni-configuration" \
            --set bpf.enableTCX=false \
            --set bpf.hostLegacyRouting=true \
            --set l7Proxy=false \
            --set sessionAffinity=true
    fi
done
cd ../cilium
./deploy_image.sh krunaljainhybridtest "${clusterPrefix}-${sufix1}"
./deploy_image.sh krunaljainhybridtest "${clusterPrefix}-${sufix2}"

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

if [ $install == "helm" ]; then
    cilium clustermesh enable --context ${clusterPrefix}-${sufix1} --enable-kvstoremesh=true
    cilium clustermesh enable --context ${clusterPrefix}-${sufix2} --enable-kvstoremesh=true
    # cilium clustermesh enable --enable-kvstoremesh=true

    cilium clustermesh status --context ${clusterPrefix}-${sufix1} --wait
    cilium clustermesh status --context ${clusterPrefix}-${sufix2} --wait

    # # # CA is passed between clusters in this step
    cilium clustermesh connect --context ${clusterPrefix}-${sufix2} --destination-context ${clusterPrefix}-${sufix1}
    # # These can be run in parallel in different bash shells

    cilium clustermesh status --context ${clusterPrefix}-${sufix1} --wait
    cilium clustermesh status --context ${clusterPrefix}-${sufix2} --wait
fi
