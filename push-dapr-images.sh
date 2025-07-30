#!/bin/bash

# Push Dapr-enabled images for AKS Store Demo
# Usage: ./push-dapr-images.sh [registry] [project] [version]
# Example: ./push-dapr-images.sh daprdemo.azurecr.io aks-store-demo dapr-latest

REGISTRY=${1:-"daprdemo.azurecr.io"}
PROJECT=${2:-"aks-store-demo"}
VERSION=${3:-"dapr-latest"}

echo "🚀 Pushing Dapr-enabled images"
echo "📦 Registry: $REGISTRY"
echo "📁 Project: $PROJECT"
echo "🏷️  Version: $VERSION"

# List of services to push
SERVICES=(
    "order-service"
    "makeline-service"  
    "product-service"
    "store-front"
    "store-admin"
    "virtual-customer"
    "virtual-worker"
)

for SERVICE in "${SERVICES[@]}"; do
    echo "Pushing ${REGISTRY}/${PROJECT}/${SERVICE}:${VERSION}..."
    docker push ${REGISTRY}/${PROJECT}/${SERVICE}:${VERSION}
    if [ $? -eq 0 ]; then
        echo "✅ ${SERVICE} pushed successfully"
    else
        echo "❌ Failed to push ${SERVICE}"
        exit 1
    fi
done

echo ""
echo "🎉 All images pushed successfully!"
echo ""
echo "📋 Pushed images:"
for SERVICE in "${SERVICES[@]}"; do
    echo "  - ${REGISTRY}/${PROJECT}/${SERVICE}:${VERSION}"
done
echo ""
echo "🎯 Update your manifest files to use these images:"
echo "image: ${REGISTRY}/${PROJECT}/order-service:${VERSION}"
echo "image: ${REGISTRY}/${PROJECT}/makeline-service:${VERSION}"
echo "# etc..."
