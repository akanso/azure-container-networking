#!/bin/bash
resources=(
  "deployment/netperf-pod"
  "ds/netperf-pod"
  "ds/netperf-host"
)

sudo PERL_MM_USE_DEFAULT=1 perl -MCPAN -e 'install JSON::Parse'

for resource in "${resources[@]}"; do
  while [[ $(kubectl get "$resource" -o jsonpath='{.status.readyReplicas}') != $(kubectl get "$resource" -o jsonpath='{.spec.replicas}') ]]; do
    echo "Waiting for $resource to be ready..."
    sleep 1
  done
done

echo "All resources are ready!"

for i in {1..1}; do
    perl runLatencyOnly.pl --nobaseline > "out-${i}.log"
    kubectl get pods -owide | grep netperf > "out-netperf-pods-${i}.log"
    cat "out-${i}.log" | grep "Localhost NetPerf TCP_RR test between POD" > "out-local-${i}.log"
    cat "out-local-${i}.log" | grep -o 'transaction rate): [0-9]\+' | sed 's/[^0-9]//g' > "out-local-${i}-raw.log"
    echo "Finished Perf Test Iter ${i}"
done

echo "Finished Perf Test"
