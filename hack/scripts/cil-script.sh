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
FILE_PATH="/etc/cni/net.d/05-cilium.conflist"

cd ../..
for unique in $sufixes; do
    # make -C ./hack/aks overlay-byocni-nokubeproxy-up-mesh \
    #     AZCLI=az REGION=westus2 SUB=$SUB \
    #     CLUSTER=${clusterPrefix}-${unique} \
    #     POD_CIDR=192.${unique}0.0.0/16 SVC_CIDR=192.${unique}1.0.0/16 DNS_IP=192.${unique}1.0.10 \
    #     VNET_PREFIX=10.${unique}0.0.0/16 SUBNET_PREFIX=10.${unique}0.10.0/24

    if [ $install == "helm" ]; then
        # cilium install -n kube-system cilium cilium/cilium --version v1.16.4 \
        # --set azure.resourceGroup=${clusterPrefix}-${unique}-rg --set cluster.id=${unique} \
        # --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
        # --set hubble.enabled=false \
        # --set envoy.enabled=false

        helm upgrade --install -n kube-system cilium cilium/cilium --version v1.16.4 \
            --set azure.resourceGroup=${clusterPrefix}-${unique}-rg \
            --set aksbyocni.enabled=false \
            --set nodeinit.enabled=false \
            --set hubble.enabled=false \
            --set envoy.enabled=false \
            --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
            --set cluster.id=${unique} \
            --set cluster.name=${clusterPrefix}-${unique} \
            --set ipam.mode=delegated-plugin \
            --set routingMode=native \
            --set endpointRoutes.enabled=true \
            --set enable-ipv4=true \
            --set enableIPv4Masquerade=false \
            --set kubeProxyReplacement=true \
            --set kubeProxyReplacementHealthzBindAddr='0.0.0.0:10256' \
            --set extraArgs="{--local-router-ipv4=169.254.23.0} {--install-iptables-rules=true}" \
            --set endpointHealthChecking.enabled=false \
            --set cni.exclusive=false \
            --set bpf.enableTCX=false \
            --set image.repository=acnpublic.azurecr.io/cilium/cilium \
            --set image.tag=krunaljainhybridtest \
            --set image.useDigest=false \
            --set bpf.hostLegacyRouting=true \
            --set l7Proxy=false \
            --set sessionAffinity=true
            FILE_PATH="/etc/cni/net.d/05-cilium.conflist"
        # Define the path to the file on AKS nodes
        FILE_PATH="/etc/cni/net.d/05-cilium.conflist"

# Get all node names
        NODES=$(kubectl get nodes -o name | cut -d'/' -f2)

# Iterate over each node and update the file
        for NODE in $NODES; do
                echo "Updating CNI config on node: $NODE"

                kubectl debug node/$NODE --image=busybox -- bash -c "
                        mkdir -p $(dirname $FILE_PATH)
                        cat <<EOF > $FILE_PATH
                        {
                            \"cniVersion\": \"0.3.1\",
                            \"name\": \"cilium\",
                            \"plugins\": [
                                {
                                    \"type\": \"cilium-cni\",
                                    \"ipam\": {
                                        \"type\": \"azure-ipam\"
                                    },
                                    \"enable-debug\": true,
                                    \"log-file\": \"/var/log/cilium-cni.log\"
                                }
                            ]
                        }
EOF
                        echo 'Updated $FILE_PATH on $NODE'
                "
        done

        echo "CNI configuration updated on all nodes."

    fi

# cilium install -n kube-system cilium cilium/cilium --version v1.16.4 \
# --set azure.resourceGroup=jpaynepoc1-${unique}-rg --set cluster.id=${unique} \
# --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
# --set hubble.enabled=false \
# --set envoy.enabled=false \
# --set extraArgs="{--local-router-ipv4=169.254.23.0}" \


# cilium config set routing-mode native
# cilium config set enable-ipv4-masquerade false
# cilium config set ipam delegated-plugin
# cilium config set local-router-ipv4 169.254.23.0
# cilium config set enable-endpoint-routes true
# cilium config set enable-endpoint-health-checking false

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
