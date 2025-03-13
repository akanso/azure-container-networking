#!/bin/bash
# Requires
# sufix1 - unique single digit whole number 1-9. Cannot match sufix2
# sufix2 - unique single digit whole number 1-9. Cannot match sufix1
# SUB - GUID for subscription
# clusterType - overlay-byocni-nokubeproxy-up-mesh is primary atm, but leaving for testing later.
# Example command: clusterPrefix=<alais> sufix1=1 sufix2=2 SUB=<GUID> clusterType=overlay-byocni-nokubeproxy-up-mesh ./cil-script.sh

sufixes="${sufix1}"
install=acn
echo "sufixes ${sufixes}"

cd ../..
for unique in $sufixes; do
    make -C ./hack/aks overlay-byocni-nokubeproxy-up-mesh \
        AZCLI=az REGION=westus2 SUB=$SUB \
        CLUSTER=${clusterPrefix}-${unique} \
        POD_CIDR=192.${unique}0.0.0/16 SVC_CIDR=192.${unique}1.0.0/16 DNS_IP=192.${unique}1.0.10 \
        VNET_PREFIX=10.${unique}0.0.0/16 SUBNET_PREFIX=10.${unique}0.10.0/24

    if [ $install == "helm" ]; then
        # cilium install -n kube-system cilium cilium/cilium --version v1.16.4 \
        # --set azure.resourceGroup=${clusterPrefix}-${unique}-rg --set cluster.id=${unique} \
        # --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
        # --set hubble.enabled=false \
        # --set envoy.enabled=false

        cilium install -n kube-system cilium cilium/cilium --version v1.16.4 \
            --set azure.resourceGroup=${clusterPrefix}-${unique}-rg \
            --set aksbyocni.enabled=false \
            --set nodeinit.enabled=false \
            --set hubble.enabled=false \
            --set envoy.enabled=false \
            --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.'${unique}'0.0.0/16}' \
            --set cluster.id=${unique} \
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
            --set bpf.hostLegacyRouting=true \
            --set l7Proxy=false \
            --set sessionAffinity=true

    else # Ignore this block for now, was testing internal resources.
        # Our Cilium image
        export CILIUM_VERSION_TAG=v1.16.2-241024
        export CILIUM_IMAGE_REGISTRY=mcr.microsoft.com/containernetworking

        # Upstream Cilium
        # export CILIUM_VERSION_TAG=v1.16.4
        # export CILIUM_IMAGE_REGISTRY=quay.io

        export DIR=1.16
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-config/cilium-config.yaml
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-agent/files
        kubectl apply -f test/integration/manifests/cilium/v${DIR}/cilium-operator/files
        envsubst '${CILIUM_VERSION_TAG},${CILIUM_IMAGE_REGISTRY}' < test/integration/manifests/cilium/v${DIR}/cilium-agent/templates/daemonset.yaml | kubectl apply -f -
        envsubst '${CILIUM_VERSION_TAG},${CILIUM_IMAGE_REGISTRY}' < test/integration/manifests/cilium/v${DIR}/cilium-operator/templates/deployment.yaml | kubectl apply -f -
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


    make test-load CNS_ONLY=true \
        AZURE_IPAM_VERSION=v0.2.0 CNS_VERSION=v1.5.32 \
        INSTALL_CNS=true INSTALL_OVERLAY=true \
        CNS_IMAGE_REPO=MCR IPAM_IMAGE_REPO=MCR
    if [ $install == "helm" ]; then
        kubectl get pods --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNETWORK:.spec.hostNetwork --no-headers=true | grep '<none>' | awk '{print "-n "$1" "$2}' | xargs -L 1 -r kubectl delete pod
    fi
done
