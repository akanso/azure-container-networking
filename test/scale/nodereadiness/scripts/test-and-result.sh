#!/bin/bash

NODES=$1
SUBNETGUID=$2
RESULTDIR="results/"

STARTTIME=$(date +"%Y%m%d%H%M%S")
./skale --nodes ${NODES} --subnet "pod-subnet" --subnet-guid ${SUBNETGUID}
mkdir -p $RESULTDIR
while true; do # TODO: add timeout
    CLUSTER_NNCS=$(kubectl get nnc -A | wc -l)
    if [ ${CLUSTER_NNCS} -eq $(( ${NODES} + 2)) ]; then
        break
    fi
    sleep 10
done

sleep 30
ENDTIME=$(date +"%Y%m%d%H%M%S")
cd results/
mkdir -p ${STARTTIME}-${ENDTIME}
cd ${STARTTIME}-${ENDTIME}
kubectl get nnc -A -o wide > get-nnc.txt
kubectl get nodes -Aowide > get-nodes.txt
kubectl logs nncscale > nncscale.log

#curl -XPOST localhost:9092/api/v1/admin/tsdb/snapshot > ${STARTTIME}-${ENDTIME}.txt
