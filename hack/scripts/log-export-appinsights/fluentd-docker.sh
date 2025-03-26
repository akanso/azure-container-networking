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
CMD ["python3", "/appinsights.py"]
EOF

# Build and Push Docker Image
docker build -t $IMAGE_NAME .
docker push $IMAGE_NAME

