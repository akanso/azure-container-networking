#! /bin/bash

DEPLOYMENT_LIST=$(kubectl -n scale-test get deployment -o jsonpath='{.items[*].metadata.name}')
for deployment_name in $DEPLOYMENT_LIST; do
    kubectl delete -n scale-test deployment $deployment_name 
    sleep 2s
done

NetworkPolicies=$(kubectl -n scale-test get networkpolicies -o jsonpath='{.items[*].metadata.name}')
for NetworkPolicy_name in $NetworkPolicies; do
    kubectl delete -n scale-test networkpolicy $NetworkPolicy_name
    sleep 2s
done

CiliumNetworkPolicies=$(kubectl -n scale-test get ciliumnetworkpolicies -o jsonpath='{.items[*].metadata.name}')
for CiliumNetworkPolicy_name in $CiliumNetworkPolicies; do
    kubectl delete -n scale-test ciliumnetworkpolicy $CiliumNetworkPolicy_name
    sleep 2s
done

Services=$(kubectl -n scale-test get services -o jsonpath='{.items[*].metadata.name}')
for Service_name in $Services; do
    kubectl delete -n scale-test service $Service_name
    sleep 2s
done
