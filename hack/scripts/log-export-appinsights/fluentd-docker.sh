#!/bin/bash

# Variables
IMAGE_NAME="acnpublic.azurecr.io/krunaljainfluentdappinsights:latest"
FLUENTD_POD_LABEL="fluentd"
NAMESPACE="kube-system"

# Create Dockerfile
cat <<EOF >Dockerfile 
FROM python:3.9-slim
WORKDIR /app
COPY appinsights.py /appinsights.py
RUN pip install opencensus-ext-azure
CMD ["sh", "-c", "while true; do python3 /appinsights.py; sleep 50; done"]
EOF

# Build and Push Docker Image
docker build -t $IMAGE_NAME .
docker push $IMAGE_NAME

