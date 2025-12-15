#!/bin/bash

# Name of the deployment
DEPLOYMENT_NAME="robot"
NAMESPACE="default"  # Change this if your deployment is in a different namespace

# Get the pod name(s) associated with the deployment
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo "Error: No pod found for deployment '$DEPLOYMENT_NAME'."
    exit 1
fi

# Delete the pod to trigger a restart
echo "Deleting pod '$POD_NAME' in deployment '$DEPLOYMENT_NAME'..."
kubectl delete pod "$POD_NAME" -n "$NAMESPACE"

echo "Pod '$POD_NAME' deleted. Kubernetes will automatically create a new one."
