#!/bin/bash

# Usage:
# ./test-vnetscale.sh <NODES>

set -ex

log () {
    local message=$1
    echo "$(date +'%Y-%m-%d %H:%M:%S'): $message"
}

# TODO
setup () {
    local NODES=$1

    kubectl create configmap node-config --from-literal=NODES_KEY=$NODES

    log "Setting up nncscale pod"
    kubectl apply -f ./files/nncscale_rbac.yaml
    kubectl apply -f ./files/nncscale_pod.yaml
    
    # TODO: Determine if this is still necessary.
    log "Setting up Prometheus"
    kubectl apply -f ./files/prom_rbac.yaml
    kubectl apply -f ./files/prom-deployment.yaml

    log "Waiting for nncscale and Prometheus pods to be ready"
    kubectl wait --for=condition=Ready --timeout=300s pod/nncscale --namespace=default
    kubectl wait --for=condition=Ready --timeout=300s pods -l app=prometheus --namespace=default

    mkdir -p results/
}

cleanup () {
    kubectl delete nodes -l type=kwok
    kubectl delete -f ./files/nncscale_rbac.yaml
    kubectl delete -f ./files/nncscale_pod.yaml
    kubectl delete -f ./files/prom_rbac.yaml
    kubectl delete -f ./files/prom-deployment.yaml
    kubectl delete configmap node-config
}

buildskale () {
    cd ./../skale
    go build -o ../nodereadiness/skale
}

testvnetscale () {
    local NODES=$1
    if [ -z $NODES ]; then
        log "Please provide the number of nodes to scale to. Usage: ./test-vnetscale.sh <NODES> <DELRECREATE>"
        exit 1
    fi
    local DELRECREATE=$2
    if [ -z $DELRECREATE ]; then
        log "Please provide whether to delete and recreate 50% of the nodes. Usage: ./test-vnetscale.sh <NODES> <DELRECREATE>"
        exit 1
    fi

    # buildskale
    setup $NODES

    # run kwok in background
    ./skale kwok \
        --cidr=155.0.0.0/16 \
        --node-ip=155.0.0.1 \
        --manage-all-nodes=false \
        --manage-nodes-with-annotation-selector=kwok.x-k8s.io/node=fake \
        --manage-nodes-with-label-selector= &> kwok.log &
    kwokpid=$!

    NODENAME=$(kubectl get nodes -o=custom-columns=NAME:.metadata.name --no-headers | head -n 1)
    log "NODENAME: $NODENAME"
    SUBNETGUID=$(kubectl get nodes $NODENAME -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/podnetwork-delegationguid}')

    # create kwok nodes
    ./skale --nodes $NODES --subnet "pod-subnet" --subnet-guid $SUBNETGUID

    # time=0
    # while true; do # TODO: add timeout
    #     if [ $time -gt 1200 ]; then
    #         log "Timeout, took longer than 10 minutes for NNCs to be ready"
    #         break
    #     fi

    #     # TODO
    #     # NNC_LIST=$(kubectl -n kube-system get nnc -o jsonpath='{.items[*].metadata.name}')
    #     # for nnc in $NNC_LIST; do
    #     #     kubectl -n scale-test delete deployment $deployment_name
    #     # done
    #     # k delete ns scale-test


    #     CLUSTER_NNCS=$(kubectl get nnc -A | wc -l)
    #     if [ ${CLUSTER_NNCS} -eq $(( ${NODES} + 2)) ]; then
    #         break
    #     fi
    #     sleep 10
    # done
    # log "All NNCs are ready"
    # sleep 60 # TOOD: Replace this with a check for all NNCs status ready

    kubectl logs nncscale -f > "results/${NODES}-$(date +%Y-%m-%d_%H-%M-%S.txt)"

    if [ "$DELRECREATE" == "true" ]; then
        # delete and recreate 50%
        HALFNODES=$(( NODES / 2 ))
        for i in $(seq 0 $(( HALFNODES - 1 ))); do
            kubectl delete node skale-node-$i
        done

        # A bit hacky + idk if this will break my metrics
        # Combined metrics would be better, but need to update the pod image
        # for that to work.
        kubectl delete -f ./files/nncscale_pod.yaml
        sleep 15
        kubectl apply -f ./files/nncscale_pod.yaml
        kubectl wait --for=condition=Ready --timeout=300s pod/nncscale --namespace=default
        
        # Recreate
        ./skale --nodes $HALFNODES --subnet "pod-subnet" --subnet-guid $SUBNETGUID

        kubectl logs nncscale -f > "results/${NODES}-delrecreate-$(date +%Y-%m-%d_%H-%M-%S.txt)"
    fi
    
    # # scale down
    # kubectl delete nodes -l type=kwok

    # # get metrics

    # cleanup

    # kill $kwokpid
}

testvnetscale $1 $2

# TODO: nncscale pod logs are getting cropped