#!/bin/bash

# Create a patch file with an unbuffered tee command
cat > patch-cilium.yaml << 'EOF'
spec:
  template:
    spec:
      initContainers:
      - name: init-log-dir
        image: busybox
        command: ["/bin/sh", "-c", "mkdir -p /var/log/cilium && chmod 755 /var/log/cilium"]
        volumeMounts:
        - name: cilium-log
          mountPath: /var/log/cilium
      containers:
      - name: cilium-agent
        command:
        - /bin/sh
        - -c
        - "cilium-agent --config-dir=/tmp/cilium/config-map 2>&1 | tee -a /var/log/cilium/cilium-agent.log"
        volumeMounts:
        - name: cilium-log
          mountPath: /var/log/cilium
      volumes:
      - name: cilium-log
        hostPath:
          path: /var/log/cilium
          type: DirectoryOrCreate
EOF

# Apply the strategic merge patch
kubectl patch ds -n kube-system cilium --patch-file patch-cilium.yaml --type=strategic

echo "Cilium DaemonSet patched to add unbuffered tee logging to /var/log/cilium/cilium-agent.log"

cat << 'EOF' > fluentd-cilium-deployment.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd-cilium-logs
  namespace: kube-system
  labels:
    k8s-app: fluentd-cilium-logs
spec:
  selector:
    matchLabels:
      k8s-app: fluentd-cilium-logs
  template:
    metadata:
      labels:
        k8s-app: fluentd-cilium-logs
    spec:
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluent/fluentd:v1.16-1
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: cilium-logs
          mountPath: /var/log/cilium
          readOnly: true
        - name: pos-dir
          mountPath: /var/fluentd/pos
        - name: fluentd-config
          mountPath: /fluentd/etc/fluent.conf
          subPath: fluent.conf
      volumes:
      - name: cilium-logs
        hostPath:
          path: /var/log/cilium
      - name: pos-dir
        emptyDir: {}
      - name: fluentd-config
        configMap:
          name: fluentd-cilium-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-cilium-config
  namespace: kube-system
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/cilium/cilium-agent.log
      pos_file /var/fluentd/pos/cilium-agent.log.pos
      tag cilium.agent
      <parse>
        @type none # Pass logs as-is
      </parse>
      read_from_head true
    </source>

    <match cilium.agent>
      @type stdout
    </match>
EOF

echo "Checking if kube-system namespace exists..."
if ! kubectl get namespace kube-system &>/dev/null; then
  echo "Error: kube-system namespace not found. Is Kubernetes running properly?"
  exit 1
fi

echo "Applying Fluentd deployment..."
kubectl apply -f fluentd-cilium-deployment.yaml

echo "Cleaning up temporary files..."
rm fluentd-cilium-deployment.yaml
rm patch-cilium.yaml

echo "Waiting for pods to be ready..."
kubectl rollout status daemonset/fluentd-cilium-logs -n kube-system

echo "Deployment complete! To view logs, run:"
echo "kubectl logs -f -n kube-system -l k8s-app=fluentd-cilium-logs"

