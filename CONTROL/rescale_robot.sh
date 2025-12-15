#!/bin/bash

# Name of the deployment
DEPLOYMENT_NAME="robot"
NAMESPACE="default"  # Change this if your deployment is in a different namespace
REPLICAS=$1  # Number of replicas to scale to (passed as an argument)

# Check if a number of replicas is passed as argument
if [ -z "$REPLICAS" ]; then
    echo "Error: You must specify the number of replicas."
    echo "Usage: $0 <number_of_replicas>"
    exit 1
fi

# Scale the deployment to the specified number of replicas
echo "Rescaling deployment '$DEPLOYMENT_NAME' to $REPLICAS replicas in namespace '$NAMESPACE'..."
kubectl scale deployment "$DEPLOYMENT_NAME" --replicas="$REPLICAS" -n "$NAMESPACE"

echo "Deployment '$DEPLOYMENT_NAME' has been rescaled to $REPLICAS replicas."
