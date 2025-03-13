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