#!/bin/bash
# Requires
# prefix1 - unique single digit whole number 1-9. Cannot match prefix2
# prefix2 - unique single digit whole number 1-9. Cannot match prefix1
# SUB - GUID for subscription
# clusterType - overlay-byocni-nokubeproxy-up-mesh is primary atm, but leaving for testing later.
# Example command: prefix1=1 prefix2=2 SUB=<GUID> clusterType=overlay-byocni-nokubeproxy-up-mesh ./cli-script.sh

prefixes="${prefix1} ${prefix2}"
install=helm
echo "Prefixes ${prefixes}"

cd ../..
for unique in $prefixes; do
    make -C ./hack/aks $clusterType \
        AZCLI=az REGION=westus2 SUB=$SUB \
        CLUSTER=cilpoc-${unique} \
        POD_CIDR=192.${unique}0.0.0/16 SVC_CIDR=192.${unique}1.0.0/16 DNS_IP=192.${unique}1.0.10 \
        VNET_PREFIX=10.${unique}0.0.0/16 SUBNET_PREFIX=10.${unique}0.0.0/16

    if [ $install == "helm" ]; then
        cilium install -n kube-system cilium cilium/cilium --version v1.16.1 \
        --set azure.resourceGroup=cilpoc-${unique} --set cluster.id=${unique} \
        --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
        --set hubble.enabled=false \
        --set envoy.enabled=false
    else # Ignore this block for now, was testing internal resources.
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

VNET_ID1=$(az network vnet show \
    --resource-group "cilpoc-${prefix1}" \
    --name "cilpoc-${prefix1}" \
    --query id -o tsv)

VNET_ID2=$(az network vnet show \
    --resource-group "cilpoc-${prefix2}" \
    --name "cilpoc-${prefix2}" \
    --query id -o tsv)

az network vnet peering create \
    -g "cilpoc-${prefix1}" \
    --name "peering-cilpoc-${prefix1}-to-cilpoc-${prefix2}" \
    --vnet-name "cilpoc-${prefix1}" \
    --remote-vnet "${VNET_ID2}" \
    --allow-vnet-access

az network vnet peering create \
    -g "cilpoc-${prefix2}" \
    --name "peering-cilpoc-${prefix2}-to-cilpoc-${prefix1}" \
    --vnet-name "cilpoc-${prefix2}" \
    --remote-vnet "${VNET_ID1}" \
    --allow-vnet-access

az aks get-credentials \
    --resource-group "cilpoc-${prefix2}" \
    --name "cilpoc-${prefix2}"

# Retaining for testing
# cilium install -n kube-system cilium cilium/cilium --version v1.16.1 --set azure.resourceGroup=cilpoc-${unique} \
# --set cluster.id=${unique} --set ipam.operator.clusterPoolIPv4PodCIDRList='{10.'${unique}'0.0.0/16}' \
# --set ipam.mode="delegated-plugin" \
# --set hubble.enabled=false \
# --set local-router-ipv4="169.254.23.0" \
# --set enable-l7-proxy=false \
# --set routing-mode="tunnel" \
# --set cni-exclusive=false \
# --set enable-tcx=false \
# --set kube-proxy-replacement-healthz-bind-address="0.0.0.0:10256"


cilium clustermesh enable --context cilpoc-${prefix1} --enable-kvstoremesh=false
cilium clustermesh enable --context cilpoc-${prefix2} --enable-kvstoremesh=false
# -- testing --
# cilium clustermesh enable --context cilpoc-${prefix1} --enable-kvstoremesh=true
# cilium clustermesh enable --context cilpoc-${prefix2} --enable-kvstoremesh=true
# -- testing --

cilium clustermesh status --context cilpoc-${prefix1} --wait
cilium clustermesh status --context cilpoc-${prefix2} --wait

# CA is passed between clusters in this step
cilium clustermesh connect --context cilpoc-${prefix1} --destination-context cilpoc-${prefix2}
# These can be run in parallel in different bash shells
# Running connectivity test from context to multi. test-namespace shows the direction of the test. 1->2, 2->1.
# Completeing both of these will take 20+~minutes. Run outside of script.
# cilium connectivity test --context cilpoc-${prefix1} --multi-cluster cilpoc-${prefix2} --test-namespace ciltest-${prefix1}-${prefix2} --force-deploy
# cilium connectivity test --context cilpoc-${prefix2} --multi-cluster cilpoc-${prefix1} --test-namespace ciltest-${prefix2}-${prefix1} --force-deploy



# -- Useful debug commands --
# cilium status --context cilpoc-${prefix1}
# cilium status --context cilpoc-${prefix2}

# az aks get-credentials --resource-group cilpoc-${prefix1} --name cilpoc-${prefix1} --overwrite-existing
# az aks get-credentials --resource-group cilpoc-${prefix2} --name cilpoc-${prefix2} --overwrite-existing

# cilium clustermesh disable --context cilpoc-${prefix1}
# cilium clustermesh disable --context cilpoc-${prefix2}
