# TODO: block comment describing this script/usage

import os
from kubernetes import client, config

# Load Kubernetes configuration
config.load_kube_config()

# Initialize Kubernetes API clients
v1 = client.CoreV1Api()
networking_v1 = client.NetworkingV1Api()

# Get namespaces
namespaces = [ns.metadata.name for ns in v1.list_namespace().items]

# Store policies and services in dictionaries
policies = {}
# FIXME: find services with externaltrafficpolicy=Cluster instead of all services. Modify the variable name and code that touch it
services = {}

# Iterate over namespaces and store policies/services
for ns in namespaces:
    print(f"Writing policies and services for namespace {ns}...")
    policies[ns] = networking_v1.list_namespaced_network_policy(ns).to_dict()
    services[ns] = v1.list_namespaced_service(ns).to_dict()

print("Policies and services have been stored in memory.")

# NetworkPolicy validation for Cilium differences
print("In Cilium, some kinds of NetworkPolicy behave differently. Reviewing NetworkPolicy configuration...")

def check_endport_policies():
    for ns in namespaces:
        endport_policies = [policy for policy in policies[ns]['items'] if any(egress.get('ports', [{}])[0].get('endPort') for egress in policy['spec'].get('egress', []))]
        if endport_policies:
            print(f"❌ Found NetworkPolicies with endPort field in namespace {ns}:")
            for policy in endport_policies:
                print(f"{ns}/{policy['metadata']['name']}")
        else:
            print(f"✅ No NetworkPolicies with endPort field found in namespace {ns}.")

def check_cidr_policies():
    for ns in namespaces:
        cidr_policies = [policy for policy in policies[ns]['items'] if any(egress.get('to', [{}])[0].get('ipBlock') for egress in policy['spec'].get('egress', []))]
        if cidr_policies:
            print(f"❌ Found NetworkPolicies with CIDRs in namespace {ns}:")
            for policy in cidr_policies:
                print(f"{ns}/{policy['metadata']['name']}")
        else:
            print(f"✅ No NetworkPolicies with CIDRs found in namespace {ns}.")

check_endport_policies()
check_cidr_policies()

# Service validation for Cilium differences
print("In Cilium, NetworkPolicy behaves differently for some kinds of Service. Reviewing Service configuration...")

SERVICES_AT_RISK = []
NO_SELECTOR_SERVICES = []
SAFE_SERVICES = []

# is the policy guaranteed to target any pod that could be selected by the service selector?
# TODO: eval if this logic is correct/complete
def match_selector(service_selector, policy_selector):
    service_labels = service_selector.get('matchLabels', {})
    policy_labels = policy_selector.get('matchLabels', {})

    if all(item in service_labels.items() for item in policy_labels.items()):
        return True

    service_expressions = service_selector.get('matchExpressions', [])
    policy_expressions = policy_selector.get('matchExpressions', [])

    for expr in service_expressions:
        key = expr['key']
        operator = expr['operator']
        values = expr.get('values', [])

        matching_expr = next((e for e in policy_expressions if e['key'] == key), None)
        if not matching_expr:
            return False

        matching_operator = matching_expr['operator']
        matching_values = matching_expr.get('values', [])

        if operator == "In" and not any(value in matching_values for value in values):
            return False
        if operator == "NotIn" and any(value in matching_values for value in values):
            return False

    return True

def check_service_risk(service_selector, namespace, service_ports):
    policies_ns = policies[namespace]['items']

    for policy in policies_ns:
        if any(not ingress.get('from') and not ingress.get('ports') for ingress in policy['spec'].get('ingress', [])):
            if match_selector(service_selector, policy['spec'].get('podSelector', {})):
                SAFE_SERVICES.append(f"{namespace}/{service}")
                return

    for policy in policies_ns:
        if any(not ingress.get('from') and ingress.get('ports') for ingress in policy['spec'].get('ingress', [])):
            if match_selector(service_selector, policy['spec'].get('podSelector', {})):
                matching_ports = [f"{port['port']}/{port['protocol']}" for ingress in policy['spec']['ingress'] for port in ingress.get('ports', [])]
                if any(svc_port in matching_ports for svc_port in service_ports):
                    SAFE_SERVICES.append(f"{namespace}/{service}")
                    return

for ns in namespaces:
    if not any(ingress.get('from') for policy in policies[ns]['items'] for ingress in policy['spec'].get('ingress', [])):
        print(f"Skipping namespace {ns} as it has no ingress NetworkPolicy rules.")
        continue

    services_ns = services[ns]['items']
    print(f"Checking NetworkPolicy targeting services with externalTrafficPolicy=Cluster in namespace {ns}...")

    for service in services_ns:
        if service['spec']['type'] in ["LoadBalancer", "NodePort"]:
            externalTrafficPolicy = service['spec'].get('externalTrafficPolicy')
            service_ports = [f"{port['port']}/{port['protocol']}" for port in service['spec'].get('ports', [])]
            if externalTrafficPolicy != "Local":
                SERVICES_AT_RISK.append(f"{ns}/{service['metadata']['name']}")
                selector = service['spec'].get('selector')
                if not selector:
                    NO_SELECTOR_SERVICES.append(f"{ns}/{service['metadata']['name']}")
                else:
                    check_service_risk(selector, ns, service_ports)

unsafe_services = list(set(SERVICES_AT_RISK) - set(SAFE_SERVICES) - set(NO_SELECTOR_SERVICES))

if not SERVICES_AT_RISK:
    print("\033[32m✔ No issues with service ingress.\033[0m")
else:
    if NO_SELECTOR_SERVICES:
        print("\nFound services without selectors which could be impacted by migration. Manual investigation is required to evaluate if ingress is allowed to the service's backend Pods. Please evaluate if these services would be impacted:")
        for service in NO_SELECTOR_SERVICES:
            print(service)
    if unsafe_services:
        print("\nFound services with selectors which could be impacted by migration. Manual investigation is required to evaluate if ingress is allowed to the service's backend Pods. Please evaluate if these services would be impacted:")
        for service in unsafe_services:
            print(service)

if NO_SELECTOR_SERVICES or len(SAFE_SERVICES) < len(SERVICES_AT_RISK) or any("❌" in check_endport_policies()) or any("❌" in check_cidr_policies()):
    print("\033[31m✘ Review above issues before migration.\033[0m")
else:
    print("\033[32m✔ Safe to migrate this cluster.\033[0m")

print("Warning: This script should be rerun if services or network policies are created, deleted, or edited.")
