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

perl runNetPerfTest.pl > out.log

echo "Finished Perf Test"
