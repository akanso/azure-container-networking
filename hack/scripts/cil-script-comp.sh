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
    if [ $install == "helm" ]; then
        cilium install -n kube-system cilium cilium/cilium --version v1.16.1 \
        --set azure.resourceGroup=${clusterPrefix}-${unique}-rg --set cluster.id=${unique} \
        --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
        --set hubble.enabled=false \
        --set envoy.enabled=false

        cilium install -n kube-system cilium cilium/cilium --version v1.16.1 \
        --set azure.resourceGroup=${clusterPrefix}-${unique} --set cluster.id=${unique} \
        --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
        --set hubble.enabled=false \
        --set envoy.enabled=false \
        --set routing.mode=native \
        --dry-run-helm-values


    else # Ignore this block for now, was testing internal resources.
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-config/cilium-config.yaml
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-agent/files
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-operator/files
        envsubst '${CILIUM_VERSION_TAG},${CILIUM_IMAGE_REGISTRY}' < test/integration/manifests/cilium/v${DIR}/cilium-agent/templates/daemonset.yaml | kubectl apply -f -
        envsubst '${CILIUM_VERSION_TAG},${CILIUM_IMAGE_REGISTRY}' < test/integration/manifests/cilium/v${DIR}/cilium-operator/templates/deployment.yaml | kubectl apply -f -
    fi
done

cd hack/scripts

cilium clustermesh enable --context ${clusterPrefix}-${sufix1} --enable-kvstoremesh=false
cilium clustermesh enable --context ${clusterPrefix}-${sufix2} --enable-kvstoremesh=false
# -- testing --
# cilium clustermesh enable --context ${clusterPrefix}-${sufix1} --enable-kvstoremesh=true
# cilium clustermesh enable --context ${clusterPrefix}-${sufix2} --enable-kvstoremesh=true
# -- testing --

cilium clustermesh status --context ${clusterPrefix}-${sufix1} --wait
cilium clustermesh status --context ${clusterPrefix}-${sufix2} --wait

# CA is passed between clusters in this step
cilium clustermesh connect --context ${clusterPrefix}-${sufix1} --destination-context ${clusterPrefix}-${sufix2}
# These can be run in parallel in different bash shells
# Running connectivity test from context to multi. test-namespace shows the direction of the test. 1->2, 2->1.
# Completeing both of these will take 20+~minutes. Run outside of script.
# cilium connectivity test --context ${clusterPrefix}-${sufix1} --multi-cluster ${clusterPrefix}-${sufix2} --test-namespace ciltest-${sufix1}-${sufix2} --force-deploy
# cilium connectivity test --context ${clusterPrefix}-${sufix2} --multi-cluster ${clusterPrefix}-${sufix1} --test-namespace ciltest-${sufix2}-${sufix1} --force-deploy



# -- Useful debug commands --
# cilium status --context ${clusterPrefix}-${sufix1}
# cilium status --context ${clusterPrefix}-${sufix2}

# az aks get-credentials --resource-group ${clusterPrefix}-${sufix1} --name ${clusterPrefix}-${sufix1} --overwrite-existing
# az aks get-credentials --resource-group ${clusterPrefix}-${sufix2} --name ${clusterPrefix}-${sufix2} --overwrite-existing

# cilium clustermesh disable --context ${clusterPrefix}-${sufix1}
# cilium clustermesh disable --context ${clusterPrefix}-${sufix2}
